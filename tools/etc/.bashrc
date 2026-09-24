# Workshop tools: default .bashrc (avoids "file not found" when bash is the shell)

[ -f /etc/bashrc ] && . /etc/bashrc

# oc, kubectl, tkn and argocd shell completion
if [ -n "$PS1" ]; then
  for tool in oc kubectl tkn argocd; do
    command -v "$tool" > /dev/null 2>&1 && source <("$tool" completion bash 2> /dev/null)
  done
fi
