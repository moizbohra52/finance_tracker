/// Runs futures concurrently and rethrows the first underlying error as-is.
///
/// Dart's record `.wait` wraps failures in a ParallelWaitError, which would
/// slip past `on AppException` handlers in controllers.
Future<(A, B)> wait2<A, B>(Future<A> a, Future<B> b) async {
  final List<Object?> r = await Future.wait<Object?>(<Future<Object?>>[a, b]);
  return (r[0] as A, r[1] as B);
}

Future<(A, B, C)> wait3<A, B, C>(Future<A> a, Future<B> b, Future<C> c) async {
  final List<Object?> r = await Future.wait<Object?>(<Future<Object?>>[
    a,
    b,
    c,
  ]);
  return (r[0] as A, r[1] as B, r[2] as C);
}

Future<(A, B, C, D)> wait4<A, B, C, D>(
  Future<A> a,
  Future<B> b,
  Future<C> c,
  Future<D> d,
) async {
  final List<Object?> r = await Future.wait<Object?>(<Future<Object?>>[
    a,
    b,
    c,
    d,
  ]);
  return (r[0] as A, r[1] as B, r[2] as C, r[3] as D);
}

Future<(A, B, C, D, E)> wait5<A, B, C, D, E>(
  Future<A> a,
  Future<B> b,
  Future<C> c,
  Future<D> d,
  Future<E> e,
) async {
  final List<Object?> r = await Future.wait<Object?>(<Future<Object?>>[
    a,
    b,
    c,
    d,
    e,
  ]);
  return (r[0] as A, r[1] as B, r[2] as C, r[3] as D, r[4] as E);
}

Future<(A, B, C, D, E, F)> wait6<A, B, C, D, E, F>(
  Future<A> a,
  Future<B> b,
  Future<C> c,
  Future<D> d,
  Future<E> e,
  Future<F> f,
) async {
  final List<Object?> r = await Future.wait<Object?>(<Future<Object?>>[
    a,
    b,
    c,
    d,
    e,
    f,
  ]);
  return (r[0] as A, r[1] as B, r[2] as C, r[3] as D, r[4] as E, r[5] as F);
}
