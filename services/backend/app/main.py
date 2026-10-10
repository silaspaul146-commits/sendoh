import hashlib, os, uuid, time
from fastapi import FastAPI, Depends, Header, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.trustedhost import TrustedHostMiddleware
from sqlalchemy import create_engine, select, text, event
from sqlalchemy.orm import sessionmaker
from .models import User, Collection, Activity, AuthSession
from .auth import router, profile
from .schemas import CollectionInput
from .service import create_collection, serialize, Conflict
from .config import load_settings
from .request_limits import RequestSizeLimit
from .invitations import router as invitation_router
from .notifications import router as notification_router
from .push import configured_sender, lifespan_for


def create_app(database_url=None):
    settings = load_settings(database_url)
    url = settings.database_url
    engine = create_engine(
        url,
        connect_args={'check_same_thread': False} if url.startswith('sqlite') else {},
        pool_pre_ping=not url.startswith('sqlite'),
    )
    if url.startswith('sqlite'):
        @event.listens_for(engine, 'connect')
        def foreign_keys(connection, _): connection.execute('PRAGMA foreign_keys=ON')
    sessions = sessionmaker(engine, expire_on_commit=False)
    sender = configured_sender()
    app = FastAPI(title='Sendoh API', version='0.4.0',
        lifespan=lifespan_for(sessions, sender, settings.environment))
    app.add_middleware(RequestSizeLimit)
    app.state.engine = engine
    app.state.settings = settings
    web_url = settings.public_web_url
    bearer = HTTPBearer(auto_error=False)

    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=list(settings.cors_origins),
            allow_credentials=False,
            allow_methods=['GET', 'POST'],
            allow_headers=['Authorization', 'Content-Type', 'Idempotency-Key'],
        )
    if settings.allowed_hosts:
        app.add_middleware(TrustedHostMiddleware, allowed_hosts=list(settings.allowed_hosts))

    def database():
        with sessions() as db:
            yield db

    def actor(credentials: HTTPAuthorizationCredentials | None = Depends(bearer), db=Depends(database)):
        if not credentials: raise HTTPException(401, 'Authentication required')
        digest = hashlib.sha256(credentials.credentials.encode()).hexdigest()
        # Legacy developer tokens must never authenticate a cloud deployment.
        user = db.scalar(select(User).where(User.token_hash == digest)) if settings.environment == 'development' else None
        if not user:
            session = db.get(AuthSession, digest)
            if session and session.expires_at > int(time.time()):
                user = db.get(User, session.user_id)
        if not user: raise HTTPException(401, 'Session expired or invalid. Sign in again.')
        return user

    @app.middleware('http')
    async def request_id(request: Request, call_next):
        request.state.request_id = str(uuid.uuid4())
        response = await call_next(request)
        response.headers['X-Request-ID'] = request.state.request_id
        if request.url.path.startswith('/api/v1/') and not request.url.path.startswith('/api/v1/public/'):
            response.headers['Cache-Control'] = 'no-store'
        return response

    @app.exception_handler(HTTPException)
    async def http_error(request, exc):
        return JSONResponse(status_code=exc.status_code, content={'error': {
            'code': {401:'AUTHENTICATION_REQUIRED',404:'NOT_FOUND',409:'CONFLICT'}.get(exc.status_code,'REQUEST_ERROR'),
            'message': str(exc.detail), 'request_id': request.state.request_id}})

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        return JSONResponse(status_code=422, content={'error': {'code': 'VALIDATION_ERROR', 'message': 'Please check the supplied fields.', 'fields': [{'path': '.'.join(map(str,e['loc'])), 'message': e['msg']} for e in exc.errors()], 'request_id': request.state.request_id}})

    @app.get('/health')
    def health(db=Depends(database)):
        db.execute(text('SELECT 1'))
        return {'status': 'ok', 'stage': settings.environment, 'version': '0.4.0',
                'push_configured': sender is not None,
                'otp_provider': settings.otp_provider, 'payments_enabled': False}

    @app.get('/')
    def root():
        return {
            'service': 'Sendoh API',
            'status': 'ok',
            'health': '/health',
            'documentation': '/docs',
        }

    @app.get('/api/v1/me')
    def me(user=Depends(actor)): return profile(user, settings.environment)

    @app.post('/api/v1/collections', status_code=201)
    def create(data: CollectionInput, idempotency_key: str = Header(min_length=8,max_length=120), user=Depends(actor), db=Depends(database)):
        if not user.display_name or not user.username: raise HTTPException(409, 'Complete your name and username before creating a collection.')
        try: return create_collection(db, user.id, idempotency_key, data, web_url)
        except Conflict as exc: raise HTTPException(409, str(exc))

    @app.get('/api/v1/collections')
    def collections(user=Depends(actor), db=Depends(database)):
        return [serialize(db,c,web_url) for c in db.scalars(select(Collection).where(Collection.organizer_id==user.id).order_by(Collection.created_at.desc()))]

    @app.get('/api/v1/collections/{collection_id}')
    def detail(collection_id: str, user=Depends(actor), db=Depends(database)):
        c=db.scalar(select(Collection).where(Collection.id==collection_id,Collection.organizer_id==user.id))
        if not c: raise HTTPException(404, 'Collection not found')
        return serialize(db,c,web_url)

    @app.get('/api/v1/public/collections/{token}')
    def public(token: str, db=Depends(database)):
        c=db.scalar(select(Collection).where(Collection.public_token==token,Collection.status=='ACTIVE'))
        if not c: raise HTTPException(404, 'Collection not found')
        return serialize(db,c,web_url,public=True)

    @app.get('/api/v1/me/activity')
    def activity(user=Depends(actor), db=Depends(database)):
        return [dict(id=a.id, message=a.message, created_at=a.created_at.isoformat()) for a in db.scalars(select(Activity).where(Activity.organizer_id==user.id).order_by(Activity.created_at.desc()))]
    app.include_router(router(database, actor, bearer, settings))
    app.include_router(invitation_router(database, actor, web_url))
    app.include_router(notification_router(database, actor, bearer, settings, sender is not None))
    return app

app = create_app()
