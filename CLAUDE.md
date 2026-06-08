# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
# Install dependencies
bundle install

# Serve locally with live reload
bundle exec jekyll serve

# Build static site to _site/
bundle exec jekyll build
```

## Architecture

This is a Jekyll blog hosted on GitHub Pages at `blog.kanotech.org` (GitHub Pages repo domain: `kanotech-org.github.io`), using the `minima` theme and `github-pages` gem bundle.

**Post format:** Posts in `_posts/` use the naming convention `YYYY-MM-DD-slug.md`. Recovered legacy posts (2010–2011) contain raw HTML content rather than Markdown, with additional front matter fields `original_url` and `wayback_url` for provenance. New posts should use standard Markdown.

**Images:** Post images live at `assets/images/posts/<post-slug>/`. Missing images that haven't been recovered from the Wayback Machine are represented as `.missing.svg` placeholder files.


**`_site/`** is the build output and is git-ignored. Do not edit files there.
