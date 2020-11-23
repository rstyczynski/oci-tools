#!/bin/bash

env_files=$1

cp -rf --preserve=mode,timestamps $env_files/tools/* $HOME/

