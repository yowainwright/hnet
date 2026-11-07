[[ -o interactive ]] || return 0

claude() {
  command "${HNET_PACKAGE_ENTRYPOINT:-${${(%):-%x}:A:h}/../../apps/hnetctl/hnetctl}" claude "$@"
}
