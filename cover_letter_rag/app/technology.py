"""Conservative technology aliases. Never rewrite source evidence."""
import re
import unicodedata


ALIASES = {
    "Python": ("python", "파이썬"),
    "React": ("react", "react.js", "reactjs", "리액트"),
    "React Native": ("react native", "리액트 네이티브"),
    "TypeScript": ("typescript", "타입스크립트"),
    "JavaScript": ("javascript", "자바스크립트"),
    "Java": ("java", "자바"),
    "Spring Boot": ("spring boot", "springboot", "스프링 부트", "스프링부트"),
    "Spring": ("spring", "스프링"),
    "Vue": ("vue", "vue.js", "vuejs", "뷰"),
    "Node.js": ("node.js", "nodejs", "노드제이에스"),
    "Next.js": ("next.js", "nextjs", "넥스트제이에스"),
    "FastAPI": ("fastapi", "패스트API", "패스트에이피아이"),
    "Docker": ("docker", "도커"),
    "Kubernetes": ("kubernetes", "k8s", "쿠버네티스"),
    "C++": ("c++", "씨플러스플러스"),
    "C#": ("c#", "씨샵"),
}


def _normalize(text: str) -> str:
    return unicodedata.normalize("NFKC", text).casefold()


_LOOKUP = {_normalize(alias): canonical for canonical, aliases in ALIASES.items() for alias in aliases}
# Longer names win so Spring Boot is not silently reduced to Spring.
_PATTERN = re.compile(
    r"(?<![\w])(?:" + "|".join(re.escape(a) for a in sorted(_LOOKUP, key=len, reverse=True))
    + r")(?![a-z0-9_+#]|\.[a-z])"
)


def canonical_technology(name: str) -> str:
    return _LOOKUP.get(_normalize(name.strip()), name.strip())


def technology_mentions(text: str) -> set[str]:
    return {_LOOKUP[m.group()] for m in _PATTERN.finditer(_normalize(text))}


def comparison_terms(text: str) -> set[str]:
    """Known aliases plus unmatched English tokens for conservative grounding."""
    normalized = _normalize(text)
    known = {"tech:" + name for name in technology_mentions(text)}
    remainder = _PATTERN.sub(" ", normalized)
    return known | set(re.findall(r"[a-z][a-z0-9.+#/-]*", remainder))


def technology_in_text(name: str, text: str) -> bool:
    canonical = canonical_technology(name)
    if canonical in ALIASES:
        return canonical in technology_mentions(text)
    return bool(re.search(r"(?<!\w)" + re.escape(_normalize(name)) + r"(?![a-z0-9_])", _normalize(text)))
