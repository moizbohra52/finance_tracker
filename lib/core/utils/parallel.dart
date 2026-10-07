/// Runs futures concurrently and rethrows the first underlying error as-is.
///
/// Dart's record `.wait` wraps failures in a ParallelWaitError, which would
/// slip past `on AppException` handlers in controllers.
Future<(A, B)> wait2<A, B>(Future<A> a, Future<B> b) async {
  final List<Object?> r = await Future.wait<Object?>(<Future<Object?>>[a, b]);
  return (r[0] as A, r[1] as B);
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
