import base64


def _b64(raw):
    return base64.b64encode(bytes(raw)).decode()


def _push(created):
    """Best-effort live delivery over the channel layer. `created` is a list of
    (device_id, QueuedEnvelope) pairs. A group_send to a group with no members is
    dropped, so a device without a socket is a no-op. The queue rows are the source
    of truth; this only saves the next poll."""
    try:
        from asgiref.sync import async_to_sync
        from channels.layers import get_channel_layer
    except Exception:
        return
    layer = get_channel_layer()
    if layer is None:
        return

    for device_id, envelope in created:
        try:
            async_to_sync(layer.group_send)(f"dev.{device_id}", {
                "type": "envelope.push",
                "id": str(envelope.id), "seq": envelope.seq,
                "blob": _b64(envelope.blob),
            })
        except Exception:
            # The rows are committed and the drain endpoint will serve them, so a dead
            # channel layer must not fail the send: the client would retry and duplicate
            # every envelope. One failure means the layer is down; stop rather than eat
            # a timeout per device. Nothing is logged because the message would carry a
            # device id.
            return
