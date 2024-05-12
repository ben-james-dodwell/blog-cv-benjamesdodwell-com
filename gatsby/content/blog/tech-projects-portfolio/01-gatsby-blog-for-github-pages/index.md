---
title: Gatsby Blog for GitHub Pages
date: "2024-03-05T17:12:32.000Z"
description: "Setting up the Gatsby React-Based Framework for my Tech Projects Portfolio and hosting with GitHub pages."
---

I have a personal project that I've wanted to start for a while, and I felt that it could be beneficial to create a small blog where I can capture some of my thoughts and share my experience as it progresses. I will cover that project in the next post but wanted to begin with some information about the setup of the blog itself.

For the website, I've utilised [Gatsby](https://www.gatsbyjs.com/) and specifically the [gatsby-starter-blog](https://www.gatsbyjs.com/starters/gatsbyjs/gatsby-starter-blog) template. I have familiarity with Gatsby from a project last year, where I used it to create a quiz that I hosted with interactive media components. The framework provides some good quality-of-life features such as templating, and markdown to HTML conversion, without being overly complicated for my needs.

I've opted to use [GitHub Pages](https://pages.github.com/) for hosting, primarily because it's simple and free. An added benefit is that it, of course, utilises a GitHub repository for source control and GitHub Actions with a continuous deployment pipeline out-of-the-box. There is also a [gh-pages](https://www.gatsbyjs.com/docs/how-to/previews-deploys-hosting/how-gatsby-works-with-github-pages/) package which I have installed that allows me to use a deploy script, making it easier to build and push the Gatsby site to GitHub Pages.