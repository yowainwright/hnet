[[ -o interactive ]] || return 0

hnetctl() {
  command "${HNET_PACKAGE_ENTRYPOINT:-${${(%):-%x}:A:h}/../../apps/hnetctl/hnetctl}" "$@"
}
