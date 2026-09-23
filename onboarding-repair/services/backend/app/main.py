import hashlib, os, uuid, time
from fastapi import FastAPI, Depends, Header, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import create_engine, select, text, event
from sqlalchemy.orm import sessionmaker
from .models import User, Collection, Activity, AuthSession
from .auth import router, profile
from .schemas import CollectionInput
from .service import create_collection, serialize, Conflict


def create_app(database_url=None):
    if os.getenv('SENDOH_ENV') != 'development':
        raise RuntimeError('This foundation uses development credentials. Set SENDOH_ENV=development locally; production authentication is not implemented.')
    app = FastAPI(title='Sendoh foundation API', version='0.1.0')
    url = database_url or os.getenv('DATABASE_URL', 'sqlite:///./sendoh.db')
    engine = create_engine(url, connect_args={'check_same_thread': False} if url.startswith('sqlite') else {})
    if url.startswith('sqlite'):
        @event.listens_for(engine, 'connect')
        def foreign_keys(connection, _): connection.execute('PRAGMA foreign_keys=ON')
    sessions = sessionmaker(engine, expire_on_commit=False)
    app.state.engine = engine
    web_url = os.getenv('PUBLIC_WEB_URL', 'http://localhost:3000').rstrip('/')
    bearer = HTTPBearer(auto_error=False)

    def database():
        with sessions() as db:
            yield db

    def actor(credentials: HTTPAuthorizationCredentials | None = Depends(bearer), db=Depends(database)):
        if not credentials: raise HTTPException(401, 'Authentication required')
        digest = hashlib.sha256(credentials.credentials.encode()).hexdigest()
        user = db.scalar(select(User).where(User.token_hash == digest))
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
        return {'status': 'ok', 'stage': 'development-foundation', 'payments_enabled': False}

    @app.get('/api/v1/me')
    def me(user=Depends(actor)): return profile(user)

    @app.post('/api/v1/collections', status_code=201)
    def create(data: CollectionInput, idempotency_key: str = Header(min_length=8,max_length=120), user=Depends(actor), db=Depends(database)):
        if not user.display_name: raise HTTPException(409, 'Complete your profile before creating a collection.')
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
    app.include_router(router(database, actor, bearer))
    return app

app = create_app()
