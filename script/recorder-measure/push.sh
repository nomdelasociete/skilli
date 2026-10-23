#!/bin/bash
# Copies what runs on the test Mac to ~/recorder-measure there (SSH host
# SKILLI_REMOTE, default skilli-mini): the probes, the runners, the models,
# the calls (make them first: mix.py, refine.py, prep_vocab.py), the test
# pages, and a venv for sherpa-onnx.
set -euo pipefail
cd "$(dirname "$0")"
H=${SKILLI_REMOTE:-skilli-mini}
ssh "$H" 'mkdir -p ~/recorder-measure/bin ~/recorder-measure/models ~/recorder-measure/audio ~/recorder-measure/out ~/recorder-measure/probe'
rsync -a work/bin/ run_engines.sh diar_run.sh batch.sh sherpa_diar.py windows.js winrun.sh tabrun.sh "$H:recorder-measure/bin/"
rsync -a work/models/whisper/ "$H:recorder-measure/models/"
rsync -a work/models/sherpa "$H:recorder-measure/models/"
rsync -a work/calls "$H:recorder-measure/audio/"
rsync -a pages "$H:recorder-measure/probe/"
[ -d work/probe ] && rsync -a work/probe/ "$H:recorder-measure/probe/"
ssh "$H" 'cd ~/recorder-measure && { [ -x venv/bin/python ] || /usr/bin/python3 -m venv venv; } && venv/bin/pip install -q sherpa-onnx soundfile numpy'
echo "pushed to $H"
