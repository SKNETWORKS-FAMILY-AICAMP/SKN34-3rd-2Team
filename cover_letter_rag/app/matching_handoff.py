"""Read a selected matching job from the authoritative store, never a client excerpt."""
import sqlite3
from datetime import datetime, time, timezone, timedelta
from pathlib import Path

from app.review_workflow import ReviewConflict, ReviewInputError, digest


class JobStoreUnavailable(RuntimeError):
    pass


def load_selected_job(path: Path, job_id: str) -> dict:
    path = Path(path).resolve()
    if not path.is_file():
        raise JobStoreUnavailable('matching_job_store_unavailable')
    try:
        # mode=ro avoids accidentally creating/upgrading the crawler's database.
        connection = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)
        connection.row_factory = sqlite3.Row
        try:
            row = connection.execute('SELECT * FROM jobs WHERE job_id = ?', (job_id,)).fetchone()
        finally:
            connection.close()
    except sqlite3.Error as exc:
        raise JobStoreUnavailable('matching_job_store_unavailable') from exc
    if row is None:
        raise ReviewInputError('selected_job_not_found')
    record = dict(row)
    if record.get('status') != 'OPEN':
        raise ReviewConflict('selected_job_closed')
    deadline = record.get('deadline')
    if deadline:
        try:
            korea = timezone(timedelta(hours=9))
            end = datetime.fromisoformat(deadline)
            if len(deadline) == 10:
                end = datetime.combine(end.date(), time.max)
            if end.tzinfo is None:
                end = end.replace(tzinfo=korea)
            if end < datetime.now(korea):
                raise ReviewConflict('selected_job_expired')
        except ValueError as exc:
            raise ReviewInputError('selected_job_deadline_unverified') from exc
    body = record.get('description') or ''
    if not body.strip() or record.get('body_is_image') in (True, 1, '1'):
        raise ReviewInputError('selected_job_full_text_unavailable')
    text = f"회사: {record.get('company', '')}\n공고: {record.get('title', '')}\n\n{body}"
    if len(text) > 50000:
        raise ReviewInputError('selected_job_text_too_long')
    source = {key: record.get(key) or '' for key in ('job_id', 'company', 'title', 'source_url', 'content_hash', 'deadline')}
    source['snapshot_hash'] = digest([source, text, record['status']])
    return {'text': text, 'source': source}
