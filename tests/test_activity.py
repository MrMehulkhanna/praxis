"""Stopping AI jobs: the Activity panel's ✕ and the AI panel's stop button.

A stop must interrupt a generation promptly (even before the first token,
while the model is still processing the prompt), close the stream to the
model server so it stops computing, and leave no job stuck as "running".
"""
import asyncio

import pytest

from core import activity


class FakeModel:
    """Stands in for adapter.run(): yields tokens, records whether it was closed."""

    def __init__(self, tokens=("a", "b", "c"), first_delay=0.0, delay=0.0):
        self.tokens, self.first_delay, self.delay = tokens, first_delay, delay
        self.closed = False
        self.produced = 0

    async def run(self):
        try:
            await asyncio.sleep(self.first_delay)          # prompt processing
            for t in self.tokens:
                self.produced += 1
                yield t
                await asyncio.sleep(self.delay)
        finally:
            self.closed = True                             # the HTTP stream would close here


def last_event(jid):
    return [e for e in activity.recent(50) if e["job"] == jid][-1]


def test_tokens_pass_through_untouched():
    async def main():
        jid = activity.new_job("chat", "hello")
        model = FakeModel()
        out = [t async for t in activity.guard(jid, model.run())]
        activity.end_job(jid, ok=True)
        return jid, out, model

    jid, out, model = asyncio.run(main())
    assert out == ["a", "b", "c"]
    assert model.closed
    assert jid not in activity.jobs
    assert last_event(jid)["stage"] == "result"


def test_stop_mid_generation_closes_the_model_stream():
    async def main():
        jid = activity.new_job("chat", "write a long story")
        model = FakeModel(tokens=[str(i) for i in range(1000)], delay=0.01)
        got = []
        with pytest.raises(activity.Cancelled):
            async for tok in activity.guard(jid, model.run()):
                got.append(tok)
                if len(got) == 3:
                    assert activity.cancel_job(jid)
        activity.end_job(jid, ok=False)
        return jid, got, model

    jid, got, model = asyncio.run(main())
    assert len(got) == 3                      # nothing after the stop is relayed
    assert model.closed and model.produced < 10
    assert jid not in activity.jobs
    assert last_event(jid)["stage"] == "cancelled"


def test_stop_during_prompt_processing_is_immediate():
    async def main():
        jid = activity.new_job("chat", "summarise this huge file")
        model = FakeModel(first_delay=30)     # would take 30 s to produce a token
        loop = asyncio.get_running_loop()
        loop.call_later(0.05, activity.cancel_job, jid)
        t0 = loop.time()
        with pytest.raises(activity.Cancelled):
            async for _ in activity.guard(jid, model.run()):
                pass
        activity.end_job(jid, ok=False)
        return jid, loop.time() - t0, model

    jid, took, model = asyncio.run(main())
    assert took < 1.0
    assert model.closed and model.produced == 0
    assert last_event(jid)["stage"] == "cancelled"


def test_client_disconnect_does_not_leave_a_running_job():
    async def main():
        jid = activity.new_job("chat", "question")
        model = FakeModel(first_delay=30)

        async def consumer():                 # what StreamingResponse iterates
            async for _ in activity.guard(jid, model.run()):
                pass
            activity.end_job(jid)             # never reached on disconnect

        task = asyncio.ensure_future(consumer())
        await asyncio.sleep(0.05)
        task.cancel()                         # Starlette does this when the client goes away
        with pytest.raises(asyncio.CancelledError):
            await task
        return jid, model

    jid, model = asyncio.run(main())
    assert jid not in activity.jobs
    assert model.closed
    assert last_event(jid)["stage"] == "error"


def test_cancel_unknown_job_is_refused():
    assert activity.cancel_job("nope") is False
