---
layout: post
title: "Getting Started with Jekyll and GitHub Pages"
date: 2025-01-16 14:30:00 +0900
categories: tutorial jekyll
tags: [jekyll, github-pages, static-site, tutorial]
---

# Getting Started with Jekyll and GitHub Pages

Jekyll is a fantastic static site generator that powers GitHub Pages. In this post, I'll share some insights about setting up a blog like this one.

## Why Jekyll?

Jekyll offers several advantages:

- **GitHub Pages integration**: Seamless deployment
- **Markdown support**: Write content in Markdown
- **Theme system**: Beautiful themes out of the box
- **Plugin ecosystem**: Extend functionality easily
- **Version control**: Your entire blog is in Git

## Basic Setup

Here's a quick overview of the setup process:

1. **Create repository**: Start with a new GitHub repository
2. **Add Jekyll files**: Create `_config.yml`, `Gemfile`, and basic structure
3. **Choose a theme**: GitHub supports several themes natively
4. **Enable GitHub Pages**: Go to repository settings and enable Pages
5. **Start writing**: Add posts to the `_posts` directory

## File Structure

A typical Jekyll blog has this structure:

```
├── _config.yml          # Site configuration
├── _posts/               # Blog posts
├── _layouts/             # Page templates (if customizing)
├── _includes/            # Reusable snippets
├── _sass/                # Sass stylesheets
├── assets/               # Images, CSS, JS
├── Gemfile               # Ruby dependencies
├── index.md              # Homepage
└── about.md              # About page
```

## Writing Posts

Posts go in the `_posts` directory with this naming convention:
`YYYY-MM-DD-title-of-post.md`

Each post starts with YAML front matter:

```yaml
---
layout: post
title: "Your Post Title"
date: 2025-01-16 14:30:00 +0900
categories: category1 category2
tags: [tag1, tag2, tag3]
---
```

## Next Steps

In future posts, I'll cover:
- Customizing themes
- Adding custom functionality
- SEO optimization
- Performance tips

Stay tuned!

---

*Have questions about Jekyll? Feel free to reach out!*