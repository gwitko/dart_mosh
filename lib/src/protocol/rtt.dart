class MoshRttEstimator {
  static const int minRto = 50;
  static const int maxRto = 1000;
  static const int minSendInterval = 20;
  static const int maxSendInterval = 250;
  static const int _maxPlausibleSample = 5000;
  static const int _initialSrtt = 1000;
  static const int _initialRttVar = 500;
  static const int _rtoVarianceMultiplier = 4;
  static const int _sendIntervalDivisor = 2;

  static const double _alpha = 1 / 8;
  static const double _beta = 1 / 4;

  double _srtt = _initialSrtt.toDouble();
  double _rttvar = _initialRttVar.toDouble();
  bool _sampled = false;

  bool get hasSample => _sampled;

  double get srtt => _srtt;

  double get rttVar => _rttvar;

  int get rto =>
      (_srtt + _rtoVarianceMultiplier * _rttvar).ceil().clamp(minRto, maxRto);

  int get sendInterval => (_srtt / _sendIntervalDivisor).ceil().clamp(
    minSendInterval,
    maxSendInterval,
  );

  void sample(int rttMs) {
    if (rttMs < 0 || rttMs >= _maxPlausibleSample) {
      return;
    }
    if (!_sampled) {
      _sampled = true;
      _srtt = rttMs.toDouble();
      _rttvar = rttMs / _sendIntervalDivisor;
      return;
    }
    _rttvar = (1 - _beta) * _rttvar + _beta * (_srtt - rttMs).abs();
    _srtt = (1 - _alpha) * _srtt + _alpha * rttMs;
  }
}
