#!/bin/bash

exec jekyll serve --incremental -H 0.0.0.0 --drafts --config=_config.yml,_local_config.yml
