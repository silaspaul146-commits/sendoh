"""Bound JSON uploads before the application parses or decodes avatar data."""
from starlette.responses import JSONResponse

class RequestSizeLimit:
    def __init__(self, app, maximum=400_000):
        self.app, self.maximum = app, maximum

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http' or scope['method'] not in ('POST', 'PUT', 'PATCH'):
            return await self.app(scope, receive, send)
        size, events = 0, []
        while True:
            message = await receive()
            if message['type'] == 'http.disconnect':
                return
            size += len(message.get('body', b''))
            if size > self.maximum:
                response = JSONResponse(status_code=413, content={
                    'error': {'code': 'REQUEST_TOO_LARGE', 'message': 'Please choose a smaller photo.'}})
                return await response(scope, receive, send)
            events.append(message)
            if not message.get('more_body', False):
                break
        async def replay():
            return events.pop(0) if events else await receive()
        await self.app(scope, replay, send)
