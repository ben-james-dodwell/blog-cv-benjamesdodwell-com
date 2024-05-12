---
title: "Creating a CV as a Website"
date: "2024-05-10T08:00:00.000Z" 
description: "Creating a CV using HTML and Tailwind CSS."
---

The initial step in creating my CV as a web page, involves adding content and then structuring the data using [Semantic HTML elements](https://developer.mozilla.org/en-US/docs/Glossary/Semantics#semantic_elements).


Subsequently, styling and visual layout are applied using CSS. I typically use the [Tailwind CSS](https://tailwindcss.com/) framework which is a [utility-first](https://tailwindcss.com/docs/utility-first) CSS framework. Utility-first generally means that there are many pre-existing styles that typically change only one thing such as the size of a font or the colour of the background. Multiple utility styles can then be added directly to HTML elements to build up the overall style of the element.

To give an example, traditional styling such as:

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

Might be rewritten as follows with Tailwind CSS:

```html
<div class="flex items-center max-w-sm mx-auto">
    <p>Hello, world!</p>
</div>
```

Arguments exist both for and against this approach, particularly concerning coupling and separation of concerns. Personally, I'm in favour of utility-based CSS, and find that Tailwind CSS allows me to be productive and create something that looks decent in a reasonable time.

[Installing Tailwind CSS](https://tailwindcss.com/docs/installation) is relatively straightforward, assuming Node.js is already installed.

```sh
npm install -D tailwindcss
npx tailwindcss init
```

Once installed and initiated, `src/input.css` can be created containing the following content:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

Another benefit of Tailwind CSS is that it generates a CSS file that contains only the styles that are actually being used. The following will build an output.css file:

```sh
npx tailwindcss -i ./src/input.css -o ./src/output.css
```

The `--watch` argument can be used to have this command run constantly, checking for changes and updating the output when necessary.

My overarching objective for the styling and layout of my CV was to support 3 different scenarios: large screen, mobile device, and print. Tailwind CSS works well for [responsive design](https://tailwindcss.com/docs/responsive-design), providing breakpoints and [print modifiers](https://tailwindcss.com/docs/hover-focus-and-other-states#print-styles).

A mobile device typically has a much smaller screen, and often a portrait aspect ratio. So, to ensure readability and maximise limited screen estate, I would stick to a single-column design. Tailwind CSS is a mobile-first framework, and so using no breakpoint modifier as default would apply to mobile devices and any other screen size unless it is overridden.

The mobile layout would look like this:

![CV layout for mobile](mobile.png)

When designing for a larger landscape screen, I wanted to maximise usage of the width, and opted for a 3-column design where the left column  takes up 1/3 of the space and a right column takes up the remaining 2/3 of the space. This would use CSS grids and the `lg:` modifier, which is the equivalent to a media query with a minimum screen width of 1024px. I could also consider larger margins, padding, or text, to improve readability and aesthetic.

The large screen layout would look like this:

![CV layout for large screens](large-screen.png)

Printing would be similar to the mobile design, with a slightly simplified design compared to that of a large screen, but with special consideration for the lack of interactiveness. For example, an anchor element would typically have easily readable and descriptive element content. For printing, either the anchor element should be hidden completely, or the element content should be the full URL so that it can be transcribed from paper to a computer. Page breaks can also be used, to avoid sections overlapping pages. There could even be an argument made to switch from sans-serif to serif font families.

The print layout would look like this:

![CV layout for print](print.png)

With the styling complete, the Terraform configuration required an update to include the output CSS file:

```hcl
resource "aws_s3_object" "css" {
  bucket       = aws_s3_bucket.cv.id
  key          = "output.css"
  source       = "../src/output.css"
  source_hash  = filemd5("../src/output.css")
  content_type = "text/css"
}
```

Finally, the Cloud Resume Challenge has been successfully completed and my CV is published at:

**https://cv.benjamesdodwell.com**