---
title: "Creating a CV as a Website"
date: "2024-05-10T08:00:00.000Z" 
description: "Creating a CV using HTML and Tailwind CSS."
---

The initial step in creating my CV as a web page, involved adding content and data structure using [Semantic HTML elements](https://developer.mozilla.org/en-US/docs/Glossary/Semantics#semantic_elements).


Subsequently, styling and visual layout are applied using CSS. I typically use the [Tailwind CSS](https://tailwindcss.com/) framework which is a [utility-first](https://tailwindcss.com/docs/utility-first) CSS framework. Utility-first generally means that there are many pre-existing styles that typically change only one thing. Multiple utility styles can then be added directly to HTML elements to build up the overall style of the element.

To give an example, a traditional styling such as:

```html
<div class="profile">
    <p>Hello, world!</p>
</div>

<style>
    .profile {
        display: flex;
        align-items: center;
        max-width: 24rem;
        margin: 0 auto;
    }
</style>
```

Might be rewritten as:

```html
<div class="flex items-center max-w-sm mx-auto">
    <p>Hello, world!</p>
</div>
```

Arguments exist both for and against this approach, pertaining to coupling and separation of concerns. Personally, I'm in favour of utility-based CSS, and find that Tailwind CSS allows me to create something that looks decent in a relatively short time.

[Installing Tailwind CSS](https://tailwindcss.com/docs/installation) is relatively straightforward, assuming Node.js is already installed.

My overarching objective for the styling and layout of my CV was to support 3 different scenarios: large screen, mobile device, and print. Tailwind CSS works well for [responsive design](https://tailwindcss.com/docs/responsive-design), providing breakpoints and [print modifiers](https://tailwindcss.com/docs/hover-focus-and-other-states#print-styles).

Large screen layout:
![CV layout for large screens](large-screen.png)

Mobile layout:
![CV layout for mobile](mobile.png)

Print layout:
![CV layout for print](print.png)

The Terraform configuration required an update to include the new CSS file:

```hcl
resource "aws_s3_object" "css" {
  bucket       = aws_s3_bucket.cv.id
  key          = "output.css"
  source       = "../src/output.css"
  source_hash  = filemd5("../src/output.css")
  content_type = "text/css"
}
```

Finally, the Cloud Resume Challenge has been successfully completed:
**https://cv.benjamesdodwell.com**