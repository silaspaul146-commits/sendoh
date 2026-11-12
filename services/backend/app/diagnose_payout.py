import os
from .providers.mesomb import Credentials, MeSombClient, ReconciliationRequired

if os.getenv("SENDOH_MESOMB_MODE") != "sandbox":
    raise SystemExit("Sandbox configuration required.")

api = MeSombClient(Credentials(
    os.environ["MESOMB_APPLICATION_KEY"],
    os.environ["MESOMB_ACCESS_KEY"],
    os.environ["MESOMB_SECRET_KEY"],
))

try:
    rows = api.lookup("85db26f3-5494-475f-9168-eba1b3861877")
    print("PAYOUT_LOOKUP: matches =", len(rows), flush=True)
    for row in rows:
        for field in ("status", "type"):
            value = row.get(field)
            if isinstance(value, str) and value.isascii() and value.replace("_", "").isalnum():
                print("PAYOUT_LOOKUP:", field, "=", value[:40], flush=True)
except ReconciliationRequired as exc:
    reason = str(exc)
    if reason.startswith("HTTP_STATUS:") or reason in (
        "TRANSPORT_OR_JSON_ERROR", "LOOKUP_SHAPE_INVALID"
    ):
        print("PAYOUT_LOOKUP:", reason, flush=True)
    else:
        print("PAYOUT_LOOKUP: unclassified provider error", flush=True)
