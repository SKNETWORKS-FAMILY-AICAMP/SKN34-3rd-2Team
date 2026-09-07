from __future__ import annotations

from typing import Any

import firebase_admin
from firebase_admin import auth, credentials, firestore
from google.api_core.exceptions import AlreadyExists
from app.review_workflow import ReviewConflict

from app.config import Settings


class FirebaseAuthenticationError(Exception):
    pass


class ResumeNotFoundError(Exception):
    pass


class ResumeAccessError(Exception):
    pass


class FirebaseGateway:
    """Firebase Admin boundary used only by the backend."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._app = self._initialize_app(settings)
        self._db = firestore.client(app=self._app)

    @staticmethod
    def _initialize_app(settings: Settings):
        try:
            return firebase_admin.get_app()
        except ValueError:
            options = {"projectId": settings.firebase_project_id} if settings.firebase_project_id else None
            return firebase_admin.initialize_app(credentials.ApplicationDefault(), options)

    def verify_id_token(self, id_token: str) -> str:
        try:
            decoded = auth.verify_id_token(id_token, app=self._app)
        except (ValueError, auth.InvalidIdTokenError, auth.ExpiredIdTokenError) as exc:
            raise FirebaseAuthenticationError("invalid or expired Firebase ID token") from exc
        uid = decoded.get("uid")
        if not isinstance(uid, str) or not uid:
            raise FirebaseAuthenticationError("Firebase ID token has no uid")
        return uid

    def get_owned_resume(self, cohort_id: str, resume_id: str, uid: str) -> dict[str, Any]:
        user = self._db.collection('users').document(uid).get().to_dict() or {}
        if user.get('isActive') is not True or user.get('cohortId') != cohort_id:
            raise ResumeAccessError('inactive user or cohort mismatch')
        snapshot = self._resume_ref(cohort_id, resume_id).get()
        if not snapshot.exists:
            raise ResumeNotFoundError("resume not found")
        data = snapshot.to_dict() or {}
        if data.get("userId") != uid:
            # Do not reveal whether another user's document exists.
            raise ResumeNotFoundError("resume not found")
        return data

    def _review_ref(self, cohort_id, resume_id, review_id):
        return self._resume_ref(cohort_id, resume_id).collection(self._settings.firestore_ai_reviews_collection).document(review_id)

    def get_ai_review(self, cohort_id, resume_id, uid, review_id):
        self.get_owned_resume(cohort_id, resume_id, uid)
        data = self._review_ref(cohort_id, resume_id, review_id).get().to_dict() or {}
        if data.get('userId') != uid or not data.get('response'):
            raise ResumeNotFoundError('review not found')
        return data['response']

    def claim_review(self, cohort_id, resume_id, uid, request_id, fingerprint):
        ref = self._review_ref(cohort_id, resume_id, request_id)
        try:
            ref.create({'userId': uid, 'fingerprint': fingerprint, 'status': 'processing', 'createdAt': firestore.SERVER_TIMESTAMP})
            return {}
        except AlreadyExists:
            state = ref.get().to_dict() or {}
            if state.get('userId') != uid or state.get('fingerprint') != fingerprint:
                raise ReviewConflict('request_id_reused_with_different_input')
            if state.get('response'):
                return state
            raise ReviewConflict('request_processing_or_failed: inspect before issuing a new request_id')

    def complete_review(self, cohort_id, resume_id, uid, request_id, response):
        self.get_owned_resume(cohort_id, resume_id, uid)
        self._review_ref(cohort_id, resume_id, request_id).update({'response': response, 'status': 'complete', 'telemetry': response['telemetry']})

    def fail_review(self, cohort_id, resume_id, uid, request_id, telemetry):
        # Keep any response committed by an ambiguous successful update recoverable.
        self._review_ref(cohort_id, resume_id, request_id).update({'status': 'failed', 'telemetry': telemetry})

    def save_ai_review(
        self,
        cohort_id: str,
        resume_id: str,
        uid: str,
        payload: dict[str, Any],
    ) -> str:
        document = self._resume_ref(cohort_id, resume_id).collection(
            self._settings.firestore_ai_reviews_collection
        ).document()
        document.set(
            {
                **payload,
                "userId": uid,
                "createdAt": firestore.SERVER_TIMESTAMP,
            }
        )
        return document.id

    def _resume_ref(self, cohort_id: str, resume_id: str):
        return (
            self._db.collection(self._settings.firestore_cohorts_collection)
            .document(cohort_id)
            .collection(self._settings.firestore_resumes_collection)
            .document(resume_id)
        )


def extract_bearer_token(authorization: str | None) -> str:
    if not authorization:
        raise FirebaseAuthenticationError("Authorization header is required")
    scheme, separator, token = authorization.partition(" ")
    if not separator or scheme.casefold() != "bearer" or not token.strip():
        raise FirebaseAuthenticationError("Authorization must use Bearer token")
    return token.strip()
