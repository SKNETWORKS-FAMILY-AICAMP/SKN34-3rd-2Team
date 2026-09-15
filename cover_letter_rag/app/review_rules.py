"""첨삭 검증이 여러 곳에서 함께 쓰는 이력서 칸 이름과 낱말 목록.

같은 목록을 review_workflow·resume_review·star_checks에 따로 적어 두면, 한쪽만 고쳤을 때 규칙이 서로 어긋난다
(2026-09-15 정리 전: 경험 칸 정규식 7곳, 칸 이름표 2벌, 항목 이름 키 2벌, 역할 과장 낱말 2벌). 목록은 여기서만 고친다.
"""
import re

# 경험을 적는 목록 칸. 항목마다 이름 칸과 설명(description) 칸이 있다.
EXPERIENCE_SECTIONS = ('projects', 'experience', 'awards', 'otherActivities', 'trainingExperience')
EXPERIENCE_SECTION_PATTERN = '|'.join(EXPERIENCE_SECTIONS)

# 항목 이름이 들어 있는 칸. 경력은 회사, 교육은 과정 이름이 항목 이름이다.
ITEM_NAME_KEYS = {'projects': 'name', 'experience': 'company', 'trainingExperience': 'course',
                  'awards': 'name', 'otherActivities': 'name'}

# "projects[2]"처럼 경험 항목을 가리키는 경로의 앞부분. 묶음은 (칸, 번호).
EXPERIENCE_ITEM = re.compile(rf'({EXPERIENCE_SECTION_PATTERN})\[(\d+)\]')
# 경험 항목의 설명 칸. 묶음은 (칸, 번호).
EXPERIENCE_DESCRIPTION = re.compile(rf'({EXPERIENCE_SECTION_PATTERN})\[(\d+)\]\.description')
# 문장으로 적는 칸: 핵심역량, 경험 설명, 자기소개서 문항 본문.
NARRATIVE_FIELD = re.compile(
    rf'coreCompetencies\.text|(?:{EXPERIENCE_SECTION_PATTERN})\[\d+\]\.description|selfIntroduction\.[^.]+\.body'
)

# 사용자에게 보이는 칸 이름. 내부 경로("coreCompetencies.text")를 문장에 쓰지 않을 때 쓴다.
SECTION_NAMES = {'coreCompetencies': '핵심역량', 'selfIntroduction': '자기소개서', 'trainingExperience': '교육',
                 'otherActivities': '활동', 'techStack': '기술 스택', 'projects': '프로젝트', 'experience': '경력',
                 'awards': '수상', 'certifications': '자격증', 'education': '학력', 'basicInfo': '기본 정보'}

# 근거 없이 수정안에 새로 들어가면 역할을 부풀린 것으로 보는 낱말.
ROLE_EXPANSION_WORDS = ('주도', '총괄', '리드', '책임', '달성')

# 항목 이름에 흔히 붙어 어느 항목인지 가려 주지 못하는 낱말.
GENERIC_NAME_TOKENS = {'개발', '서비스', '시스템', '프로젝트', '기반', '관리', '구축', '과정', '교육', '참여', '팀',
                       '웹', '앱', '플랫폼', '구현', '활동', '동아리', '수상', '대회', '주식회사', '(주)'}
# 새 프로젝트 이름에 흔히 붙어 사실을 담지 않는 낱말. 이름이 답에 있는 말인지 볼 때 세지 않는다.
NEW_PROJECT_NAME_GENERIC = GENERIC_NAME_TOKENS | {'과제', '개인', '토이', '사이드', '화면', '기능', '페이지', '연동', '만들기'}
# 프로젝트 이름이 이 낱말로만 되어 있으면 무엇을 만들었는지 없이 형태만 적힌 이름이다.
PROJECT_FORM_WORDS = {'부트캠프', '개인', '과제', '토이', '사이드', '프로젝트', '수업', '학교', '동아리', '팀', '졸업', '캡스톤',
                      '미니', '실습', '교육', '과정', '팀프로젝트', '개인과제'}

# 부정 표현. 원문과 수정안 사이에서 생기거나 사라지면 뜻이 바뀌었을 수 있다.
NEGATION = r'않|못|없|아니|미완료|미구현'
# 한 일 자체를 부정하는 표현. 뒤집히면 하지 않은 일을 한 것처럼 쓰게 되니 계속 막는다.
WORK_NEGATION = re.compile(
    r'않았|못|없었|아니었|미완료|미구현|(?:경험|사용한\s*적|해\s*본\s*적|써\s*본\s*적)(?:은|이)?\s*없'
)
# "없"·"아니"·"못"이 들어 있지만 부정이 아닌 낱말. "끊임없이 배우고 성장하겠습니다"를 부정으로 잡아 안내가 붙었다
# (2026-09-15 새 케이스 v16m). 부정 검사 전에 지운다.
NOT_NEGATION_WORDS = re.compile(
    r'끊임\s*없|어김\s*없|틀림\s*없|빠짐\s*없|거침\s*없|아낌\s*없|쉴\s*새\s*없|빈틈\s*없|변함\s*없|다름\s*없|손색\s*없|'
    r'하염\s*없|상관\s*없|관계\s*없|뿐(?:만)?\s*아니|못지\s*않|마지\s*않'
)
