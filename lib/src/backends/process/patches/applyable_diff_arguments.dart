/// Git `diff` options producing a patch `git apply` can replay.
///
/// `--binary` and `--full-index` carry the content a plain text diff omits.
/// `--no-textconv` and `--no-ext-diff` ignore the repository's diff drivers
/// and external diff command, so the patch holds file contents rather than
/// what those commands print. The explicit prefixes override `diff.noprefix`
/// and `diff.mnemonicPrefix`.
const List<String> applyableDiffArguments = <String>[
  '--binary',
  '--full-index',
  '--no-color',
  '--no-textconv',
  '--no-ext-diff',
  '--src-prefix=a/',
  '--dst-prefix=b/',
];
