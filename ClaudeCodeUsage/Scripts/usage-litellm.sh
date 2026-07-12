#!/bin/bash

/opt/homebrew/bin/dp-devinfra litellm usage \
  | tail -1 \
  | awk '{print $NF}'
