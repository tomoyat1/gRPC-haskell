{ darwin, stdenv, lib, fetchgit, autoconf, automake, libtool, which, zlib
, openssl
}:

stdenv.mkDerivation rec {
  name    = "grpc-${version}";
  version = "1.12.0-${lib.strings.substring 0 7 rev}";
  rev     = "bec3b5ada2c5e5d782dff0b7b5018df646b65cb0";
  src = fetchgit {
    inherit rev;
    url    = "https://github.com/grpc/grpc.git";
    sha256 = "0kcyg6zirqivvjgbdcplqq8p5zli2w1q2y3wr8rfwwri3812bqm2";
  };

  # `grpc`'s `Makefile` does some magic to detect the correct `ld` and `strip`
  # to use along with their flags, too.  If Nix supplies `$LD` and `$STRIP` then
  # this auto-detection fails and the build fails, which is why we unset the
  # environment variables here and let the `Makefile` set them.
  preBuild = ''
    unset LD
    unset STRIP
  '';

  preInstall = "export prefix";

  buildInputs = [
    autoconf
    automake
    libtool
    which
    zlib
    openssl
  ];

  # Some versions of `ar` (such as the one provided by OS X) require an explicit
  # `-r` flag, whereas other versions assume `-r` is the default if no mode is
  # specified.  For example, OS X requires the `-r` flag, so as a precaution we
  # always specify the flag.
  AROPTS = "-r";
}
