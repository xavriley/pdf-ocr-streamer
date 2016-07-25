# Extracting text from UK Company Accounts
## Using Docker, Tika, Tesseract and Heroku

## Why

The open data movement is only as good as the projects that use it.
There's a lot to complain about, but with company accounts being available for free in the UK
we have an *incredible* resource for transparency at all levels of the economy - if we are willing
to use it. My motivation for setting this up was that I already knew how good Tesseract can be at
extracting text from accounts (not perfect, but still useful) but it requires a fair amount of know-how
to set up. Heroku (where I now work) recently annouced support for `Dockerfile` based apps and this
seemed like a good opportunity to kick the tyres on that, whilst making a contribution to anyone working
with UK company data.

I'm hoping to integrate this with the PFI Explorer project that I worked on for a hack day in 2014

https://pfi-explorer.herokuapp.com

## About

This is a test project that comprises two apps

Live site: https://dockertikatest.herokuapp.com/
Code: https://github.com/xavriley/tika-tesseract-docker

^^^ This is a `Dockerfile` based app, deployed to Heroku running Apache Tika with Tesseract embedded.
It works well, but it is subject to the 30 second timeout for web requests so I needed to work around that,
specifically for UK Company accounts pdfs as these are large images and several pages in length.

Live site: https://pdf-ocr-streamer.herokuapp.com/
Code: this repo

This app acts as a proxy to the Tika instance above. It can retrieve a PDF (or XBRL) of UK accounts for a company.
The resulting PDF or XBRL is then posted to the `/unpack` endpoint of Tika which returns a zip file of individual assets (including images embedded in PDFs).
Finally, the script iterates through these images and submits them for text extraction to the `/tika` endpoint. This will perform OCR on images if necessary,
and (here's the crucial bit) *stream the results to the browser*. This works around the 30 second limit for Heroku.

### Warning

The code is terrible so please take this as a starting point rather than relying on it as a production service. There's no warranty of any kind here.

The architecture is decent though. The number of Tika instances can be scaled independently of the proxy with the power of the Heroku slider.
The `Dockerfile` approach also means it's trivial to run locally, provided you have Docker working.

### Usage

You're free to test out the live web service but I take no responsibility if you try to use it in production - let me know on Twitter @xavriley how it works out.

### Future improvements

* Turn this into a Heroku button?
* Cache the extracted files to S3 - this makes sense for UK accounts as they don't change
* Save the text to a database/elasticsearch and allow queries
* Allow the URL structure to point to the files in their original location on the web
* Basic entity extraction for company names
* Return hocr if requested (requires changes to Tika source)
* Make the service more generic for non UK Accounts PDFs?
