"""Tests for the markdown link checker."""

import tempfile
from pathlib import Path

from link_checker import check_file, extract_links, validate_local_link


class TestExtractLinks:
    def test_basic_link(self):
        md = "[click here](https://example.com)"
        links = extract_links(md)
        assert len(links) == 1
        assert links[0]["text"] == "click here"
        assert links[0]["url"] == "https://example.com"
        assert links[0]["is_external"] is True

    def test_local_link(self):
        md = "[readme](./docs/readme.md)"
        links = extract_links(md)
        assert len(links) == 1
        assert links[0]["is_external"] is False

    def test_anchor_link(self):
        """Anchor links like #section should be detected as anchors."""
        md = "[section](#installation)"
        links = extract_links(md)
        assert len(links) == 1
        # BUG 1 will cause this to fail: anchors start with # not /
        assert links[0]["is_anchor"] is True

    def test_multiple_links(self):
        md = "[a](https://a.com) text [b](./b.md) more [c](#top)"
        links = extract_links(md)
        assert len(links) == 3


class TestValidateLocalLink:
    def test_relative_file(self):
        """Relative links should resolve against base_dir, not cwd."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create a file inside a subdirectory
            subdir = Path(tmpdir) / "docs"
            subdir.mkdir()
            target = subdir / "guide.md"
            target.write_text("# Guide")
            # Relative link "guide.md" should resolve against base_dir=subdir
            result = validate_local_link("guide.md", subdir)
            assert result is True

    def test_missing_file(self):
        result = validate_local_link("nonexistent.md", Path("/tmp"))
        assert result is False

    def test_anchor_only(self):
        result = validate_local_link("#section", Path("/tmp"))
        assert result is True


class TestCheckFile:
    def test_returns_issues_not_links(self):
        """check_file should return only issues, not all links."""
        with tempfile.NamedTemporaryFile(suffix=".md", mode="w", delete=False) as f:
            # Write a file with one valid external link and one broken local link
            f.write("[good](https://example.com)\n[bad](./nonexistent.md)\n")
            f.flush()
            issues = check_file(f.name)
            # BUG 3 will cause this to fail: returns all links instead of issues
            # Should have exactly 1 issue (the broken local link)
            assert len(issues) == 1
            assert issues[0]["issue"] == "Broken local link"
