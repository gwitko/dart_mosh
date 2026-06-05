import '../constants.dart';
import '../exception.dart';

class MoshReplayFilter {
  MoshReplayFilter({this.windowSize = moshDefaultReplayWindow}) {
    if (windowSize <= 0) {
      throw const MoshException('Replay window must be positive.');
    }
  }

  final int windowSize;
  final Set<int> _seen = <int>{};
  int _highest = -1;

  bool accept(int sequence) {
    if (sequence < 0) {
      throw const MoshException('Replay sequence cannot be negative.');
    }

    if (_highest < 0) {
      _highest = sequence;
      _seen.add(sequence);
      return true;
    }

    if (sequence > _highest) {
      _highest = sequence;
      _seen.add(sequence);
      _seen.removeWhere((value) => value <= _highest - windowSize);
      return true;
    }

    if (sequence <= _highest - windowSize) {
      return false;
    }

    return _seen.add(sequence);
  }
}
