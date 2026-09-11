"""수업 자료 → 정리 노트 LangGraph 파이프라인.

04_instructor_git_study_agent.ipynb 의 노드 구성을 그대로 옮겼다.

    analyze_files → compile_report → review_report
        ├─ 통과 → create_review_material
        └─ 보완 → revise_report → create_review_material
"""

from __future__ import annotations

import os
from functools import lru_cache
from typing import TypedDict

from langchain_core.prompts import ChatPromptTemplate
from langchain_openai import ChatOpenAI
from langgraph.graph import END, START, StateGraph
from pydantic import BaseModel, Field

LEARNER_LEVEL = "수업을 일부 놓친 초보자"
MAX_CHARS_PER_FILE = 18_000


class Material(TypedDict):
    path: str
    commit: str
    content: str
    truncated: bool


class FileSummary(TypedDict):
    path: str
    commit: str
    summary: str


class StudyAgentState(TypedDict, total=False):
    scope_label: str
    learner_level: str
    commits: list[str]
    materials: list[Material]
    file_summaries: list[FileSummary]
    draft_report: str
    review_passed: bool
    review_feedback: str
    review_markdown: str


class ReviewResult(BaseModel):
    passed: bool = Field(description="핵심 내용이 빠짐없이 명확하면 true")
    feedback: str = Field(description="부족한 내용과 구체적인 보완 지시")


def study_notes_model_name() -> str:
    return (
        os.getenv("STUDY_NOTES_MODEL", "").strip()
        or os.getenv("LMS_NODE_MODEL", "").strip()
        or "gpt-5.6-sol"
    )


@lru_cache
def _llm() -> ChatOpenAI:
    return ChatOpenAI(model=study_notes_model_name(), max_retries=2)


FILE_ANALYSIS_PROMPT = ChatPromptTemplate.from_messages([
    (
        "system",
        "당신은 AI 부트캠프 수업자료를 분석하는 교육 전문가입니다.\n"
        "학습자가 실제 코드를 다시 실행할 수 있도록 정확하고 구체적으로 설명하세요.\n"
        "자료에 없는 내용을 수업 내용인 것처럼 만들지 마세요.",
    ),
    (
        "human",
        "학습자 수준: {learner_level}\n"
        "파일: {file_path}\n"
        "잘림: {truncated}\n\n"
        "다음 수업자료를 분석하세요.\n\n"
        "{content}\n\n"
        "아래 항목으로 정리하세요.\n"
        "1. 이 파일의 학습 목표\n"
        "2. 핵심 개념\n"
        "3. 코드 실행 흐름\n"
        "4. 중요한 클래스·함수·도구\n"
        "5. 실행 전 필요한 환경·API·데이터\n"
        "6. 예상 오류와 확인할 부분\n"
        "7. 직접 해볼 작은 실습",
    ),
])

REPORT_PROMPT = ChatPromptTemplate.from_messages([
    (
        "system",
        "당신은 여러 수업 파일의 분석을 하나의 학습 노트로 편집합니다.\n"
        "중복 설명은 합치고, 파일 사이의 선후 관계와 전체 실행 흐름을 분명히 보여주세요.\n"
        "초보자가 복습할 수 있으면서 취업 포트폴리오 회고에도 활용할 수 있게 작성하세요.",
    ),
    (
        "human",
        "수업 범위: {scope_label}\n"
        "학습자 수준: {learner_level}\n"
        "변경 커밋: {commits}\n\n"
        "파일별 분석:\n{summaries}\n\n"
        "다음 구조의 한국어 Markdown 보고서를 작성하세요.\n\n"
        "# 날짜별 수업 정리\n"
        "## 오늘의 핵심 한 문장\n"
        "## 전체 수업 흐름\n"
        "## 파일별 학습 내용\n"
        "## 핵심 코드와 개념\n"
        "## 이전 학습과의 연결\n"
        "## 실행 체크리스트\n"
        "## 내가 직접 해볼 실습\n"
        "## 포트폴리오 회고 포인트\n\n"
        "변경된 파일 경로를 반드시 표시하세요. 자료에 없는 내용은 지어내지 마세요.",
    ),
])

REVIEW_PROMPT = ChatPromptTemplate.from_messages([
    (
        "system",
        "당신은 수업 요약 품질 검토자입니다.\n"
        "원본 파일별 분석과 통합 보고서를 비교해 누락, 잘못된 연결, 실행 정보 부족을 검사하세요.",
    ),
    (
        "human",
        "파일별 분석:\n{summaries}\n\n"
        "통합 보고서:\n{report}\n\n"
        "다음 기준을 모두 만족하면 passed=true로 평가하세요.\n"
        "- 모든 변경 파일이 언급됨\n"
        "- 핵심 개념과 코드 흐름이 포함됨\n"
        "- 필요한 API·데이터·환경이 포함됨\n"
        "- 자료에 없는 사실을 단정하지 않음\n"
        "- 학습자가 실행할 다음 단계가 명확함",
    ),
])

REVISION_PROMPT = ChatPromptTemplate.from_messages([
    (
        "system",
        "품질 검토 의견을 반영해 수업 보고서를 정확하고 완결된 Markdown 문서로 수정하세요.",
    ),
    (
        "human",
        "기존 보고서:\n{report}\n\n"
        "검토 의견:\n{feedback}\n\n"
        "기존 보고서의 유용한 내용은 유지하고 지적받은 부분만 명확하게 보완하세요.",
    ),
])

REVIEW_MATERIAL_PROMPT = ChatPromptTemplate.from_messages([
    (
        "system",
        "수업 보고서를 바탕으로 학습자가 스스로 이해도를 점검할 복습 자료를 만드세요.",
    ),
    (
        "human",
        "수업 보고서:\n{report}\n\n"
        "다음을 한국어 Markdown으로 작성하세요.\n"
        "## 복습 문제\n"
        "- 개념 확인 문제 3개\n"
        "- 코드 흐름 문제 2개\n"
        "- 응용 문제 1개\n\n"
        "## 정답과 해설\n"
        "각 문제의 정답과 짧은 해설을 작성하세요.",
    ),
])


def _summaries_text(summaries: list[FileSummary]) -> str:
    return "\n\n".join(f"### {item['path']}\n{item['summary']}" for item in summaries)


def _content(response) -> str:
    content = response.content
    if isinstance(content, list):
        return "".join(
            part.get("text", "") if isinstance(part, dict) else str(part) for part in content
        )
    return str(content)


def analyze_files(state: StudyAgentState) -> dict:
    chain = FILE_ANALYSIS_PROMPT | _llm()
    summaries: list[FileSummary] = []
    for material in state["materials"]:
        response = chain.invoke({
            "learner_level": state["learner_level"],
            "file_path": material["path"],
            "truncated": "있음" if material["truncated"] else "없음",
            "content": material["content"],
        })
        summaries.append({
            "path": material["path"],
            "commit": material["commit"],
            "summary": _content(response),
        })
    return {"file_summaries": summaries}


def compile_report(state: StudyAgentState) -> dict:
    response = (REPORT_PROMPT | _llm()).invoke({
        "scope_label": state["scope_label"],
        "learner_level": state["learner_level"],
        "commits": ", ".join(c[:8] for c in state["commits"]) or "없음",
        "summaries": _summaries_text(state["file_summaries"]),
    })
    return {"draft_report": _content(response)}


def review_report(state: StudyAgentState) -> dict:
    reviewer = _llm().with_structured_output(ReviewResult)
    try:
        result = (REVIEW_PROMPT | reviewer).invoke({
            "summaries": _summaries_text(state["file_summaries"]),
            "report": state["draft_report"],
        })
    except Exception:  # 검토 실패는 초안을 그대로 쓴다.
        return {"review_passed": True, "review_feedback": "검토를 완료하지 못해 초안을 유지합니다."}
    if not isinstance(result, ReviewResult):
        return {"review_passed": True, "review_feedback": "검토 결과를 읽지 못해 초안을 유지합니다."}
    return {"review_passed": result.passed, "review_feedback": result.feedback}


def route_after_review(state: StudyAgentState) -> str:
    return "finish" if state.get("review_passed") else "revise"


def revise_report(state: StudyAgentState) -> dict:
    response = (REVISION_PROMPT | _llm()).invoke({
        "report": state["draft_report"],
        "feedback": state["review_feedback"],
    })
    return {"draft_report": _content(response)}


def create_review_material(state: StudyAgentState) -> dict:
    response = (REVIEW_MATERIAL_PROMPT | _llm()).invoke({"report": state["draft_report"]})
    return {"review_markdown": _content(response)}


@lru_cache
def build_graph():
    workflow = StateGraph(StudyAgentState)
    workflow.add_node("analyze_files", analyze_files)
    workflow.add_node("compile_report", compile_report)
    workflow.add_node("review_report", review_report)
    workflow.add_node("revise_report", revise_report)
    workflow.add_node("create_review_material", create_review_material)

    workflow.add_edge(START, "analyze_files")
    workflow.add_edge("analyze_files", "compile_report")
    workflow.add_edge("compile_report", "review_report")
    workflow.add_conditional_edges(
        "review_report",
        route_after_review,
        {"finish": "create_review_material", "revise": "revise_report"},
    )
    workflow.add_edge("revise_report", "create_review_material")
    workflow.add_edge("create_review_material", END)
    return workflow.compile()


def generate_study_note(
    *,
    scope_label: str,
    commits: list[str],
    materials: list[Material],
) -> tuple[str, str]:
    """(reportMarkdown, reviewMarkdown)을 반환한다."""
    if not materials:
        raise ValueError("분석할 수업 자료가 없습니다.")
    result = build_graph().invoke(
        {
            "scope_label": scope_label,
            "learner_level": LEARNER_LEVEL,
            "commits": commits,
            "materials": materials,
        },
        config={"run_name": "lms_study_notes"},
    )
    return result.get("draft_report", ""), result.get("review_markdown", "")
