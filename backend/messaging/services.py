import base64


def _b64(raw):
    return base64.b64encode(bytes(raw)).decode()


def _push(created):
    """Best-effort live delivery over the realtime channel layer. `created` is a list of
    (device_id, QueuedEnvelope). Safe no-op if the realtime consumer isn't running or the
    device has no socket (a group_send to a group with no members is dropped). The durable
    queue rows are the source of truth; this is only an optimization (§A6)."""
    try:
        from asgiref.sync import async_to_sync
        from channels.layers import get_channel_layer
    except Exception:
        return
    layer = get_channel_layer()
    if layer is None:
        return
    for dev_id, env in created:
        try:
            async_to_sync(layer.group_send)(f"dev.{dev_id}", {
                "type": "envelope.push",
                "id": str(env.id), "seq": env.seq,
                "blob": _b64(env.blob),
            })
        except Exception:
            # The rows are committed and GET /me/envelopes will serve them, so a dead
            # channel layer must never fail the send — the client would retry and
            # duplicate every envelope (§A6). One failure means the layer is down, so
            # stop rather than wait out a timeout per device. Nothing is logged: the
            # message would carry a device id (§A11.4).
            return
