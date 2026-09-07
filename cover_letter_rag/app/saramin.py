from pydantic import BaseModel, ConfigDict, Field


class SaraminModel(BaseModel):
    """사람인 Open API 응답을 수용하는 읽기 전용 모델."""

    model_config = ConfigDict(extra="ignore", populate_by_name=True)


class SaraminCodeName(SaraminModel):
    code: str | int
    name: str


class SaraminExperienceLevel(SaraminCodeName):
    min: int | None = None
    max: int | None = None


class SaraminCompanyDetail(SaraminModel):
    href: str
    name: str


class SaraminCompany(SaraminModel):
    detail: SaraminCompanyDetail


class SaraminPosition(SaraminModel):
    title: str
    industry: SaraminCodeName
    location: SaraminCodeName
    job_type: SaraminCodeName = Field(alias="job-type")
    job_mid_code: SaraminCodeName = Field(alias="job-mid-code")
    job_code: SaraminCodeName = Field(alias="job-code")
    experience_level: SaraminExperienceLevel = Field(alias="experience-level")
    required_education_level: SaraminCodeName = Field(
        alias="required-education-level"
    )


class SaraminJob(SaraminModel):
    url: str
    active: int
    company: SaraminCompany
    position: SaraminPosition
    keyword: str = ""
    salary: SaraminCodeName
    id: str
    posting_timestamp: str = Field(alias="posting-timestamp")
    posting_date: str = Field(alias="posting-date")
    modification_timestamp: str = Field(alias="modification-timestamp")
    opening_timestamp: str = Field(alias="opening-timestamp")
    expiration_timestamp: str = Field(alias="expiration-timestamp")
    expiration_date: str = Field(alias="expiration-date")
    close_type: SaraminCodeName = Field(alias="close-type")
    read_count: str = Field(alias="read-cnt")
    apply_count: str = Field(alias="apply-cnt")


class SaraminJobs(SaraminModel):
    count: int
    start: int
    total: str | int
    job: list[SaraminJob]


class SaraminJobSearchResponse(SaraminModel):
    jobs: SaraminJobs

