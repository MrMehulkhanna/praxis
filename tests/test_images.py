import tempfile
import pathlib
import base64
from core.gateway.iface import attach_images


def test_attach_images_data_uri():
    messages = [{"role": "user", "content": "What is in this picture?"}]
    data_uri = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    res = attach_images(messages, [data_uri])
    assert len(res) == 1
    content = res[0]["content"]
    assert isinstance(content, list)
    assert content[0] == {"type": "text", "text": "What is in this picture?"}
    assert content[1] == {"type": "image_url", "image_url": {"url": data_uri}}


def test_attach_images_file_path():
    with tempfile.NamedTemporaryFile(suffix=".png") as f:
        f.write(b"fake-image-bytes")
        f.flush()
        messages = [{"role": "user", "content": "Analyze screenshot"}]
        res = attach_images(messages, [f.name])
        assert len(res) == 1
        content = res[0]["content"]
        assert isinstance(content, list)
        assert content[0] == {"type": "text", "text": "Analyze screenshot"}
        assert content[1]["type"] == "image_url"
        url = content[1]["image_url"]["url"]
        assert url.startswith("data:image/png;base64,")


def test_attach_images_file_uri():
    with tempfile.NamedTemporaryFile(suffix=".jpg") as f:
        f.write(b"fake-jpeg-bytes")
        f.flush()
        messages = [{"role": "user", "content": "Check this"}]
        res = attach_images(messages, ["file://" + f.name])
        assert len(res) == 1
        url = res[0]["content"][1]["image_url"]["url"]
        assert url.startswith("data:image/jpeg;base64,")


def test_attach_images_empty_messages():
    data_uri = "data:image/png;base64,abc"
    res = attach_images([], [data_uri])
    assert len(res) == 1
    assert res[0]["role"] == "user"
    assert res[0]["content"][1]["image_url"]["url"] == data_uri


def test_attach_images_dict_format():
    dict_img = {"type": "image_url", "image_url": {"url": "https://example.com/test.png"}}
    messages = [{"role": "user", "content": "Check url"}]
    res = attach_images(messages, [dict_img])
    assert res[0]["content"][1] == dict_img
