"""The organizer's Home: what was collected this month and who contributed.

"Collected this month" is money collected for the organizer's own groups in the
current calendar month (Africa/Douala): Mobile Money confirmed by the provider
in that month plus cash the organizer recorded in that month. It is not a
wallet balance. Recent activity is built from confirmation evidence, so
"Marie contributed" only appears once her payment was verified.
"""
import time
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select

from .models import CashRecord, Collection, ProviderPayment, ProviderPaymentEvent, User

DOUALA = timezone(timedelta(hours=1))  # Cameroon: UTC+1, no daylight saving


def month_start(now=None):
    local = datetime.fromtimestamp(now or time.time(), DOUALA)
    return int(local.replace(day=1, hour=0, minute=0, second=0, microsecond=0).timestamp()), local.strftime('%Y-%m')


def router(database, actor):
    routes = APIRouter(prefix='/api/v1/me')

    @routes.get('/home')
    def home(user=Depends(actor), db=Depends(database)):
        start, month = month_start()
        confirmed = db.execute(
            select(ProviderPayment, ProviderPaymentEvent.created_at, Collection.name)
            .join(ProviderPaymentEvent, ProviderPaymentEvent.payment_id == ProviderPayment.id)
            .join(Collection, Collection.id == ProviderPayment.collection_id)
            .where(Collection.organizer_id == user.id, ProviderPaymentEvent.status == 'SUCCEEDED',
                   ProviderPayment.status == 'SUCCEEDED')  # a later refund no longer counts
            .order_by(ProviderPaymentEvent.created_at.desc())).all()
        this_month = [(p, at, name) for p, at, name in confirmed if at >= start]
        cash = db.execute(select(CashRecord.amount, CashRecord.collection_id)
                          .join(Collection, Collection.id == CashRecord.collection_id)
                          .where(Collection.organizer_id == user.id, CashRecord.updated_at >= start)).all()
        mobile = sum(p.amount for p, _, _ in this_month)
        cash_total = sum(a for a, _ in cash)
        collections = {p.collection_id for p, _, _ in this_month} | {cid for _, cid in cash}
        names = dict(db.execute(select(User.id, User.display_name).where(
            User.id.in_({p.payer_id for p, _, _ in confirmed[:10]}))).all()) if confirmed else {}
        recent = [dict(kind='CONTRIBUTED', name=names.get(p.payer_id, 'A member'), amount=p.amount,
                       collection_id=p.collection_id, collection_name=name, at=at)
                  for p, at, name in confirmed[:10]]
        return dict(collected_this_month=dict(amount=mobile + cash_total, mobile_money=mobile,
                                              cash=cash_total, collections=len(collections),
                                              month=month, environment='SANDBOX'),
                    recent=recent)

    return routes
