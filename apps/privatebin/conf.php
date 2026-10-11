;<?php http_response_code(403); /*
; PrivateBin configuration for the ePHPm recipe.
;
; This is PrivateBin's stock cfg/conf.sample.php reduced to the keys this
; recipe touches; every other option keeps its default. For the full list of
; options copy cfg/conf.sample.php from the PrivateBin release you run and
; mount it at /srv/cfg/conf.php (same path as the official image).
; Reference: https://github.com/PrivateBin/PrivateBin/blob/master/cfg/conf.sample.php

[main]
; name = "PrivateBin"
; set to the public URL when PrivateBin runs behind a proxy or in a sub-path
; basepath = "https://privatebin.example.com/"
discussion = true
opendiscussion = false
password = true
fileupload = false
burnafterreadingselected = false
defaultformatter = "plaintext"
sizelimit = 10485760
template = "bootstrap5"
languageselection = false

[expire]
default = "1week"

[expire_options]
5min = 300
10min = 600
1hour = 3600
1day = 86400
1week = 604800
1month = 2592000
1year = 31536000
never = 0

[formatter_options]
plaintext = "Plain Text"
syntaxhighlighting = "Source Code"
markdown = "Markdown"

[traffic]
; minimum interval in seconds between pastes from the same IP (0 disables)
limit = 10

[purge]
limit = 300
batchsize = 10

[model]
; pastes as files under /srv/data (the `data` volume). PDO (MySQL/PostgreSQL)
; and S3/GCS backends are supported by PrivateBin as in the official image —
; see the sample config.
class = Filesystem

[model_options]
dir = PATH "data"
