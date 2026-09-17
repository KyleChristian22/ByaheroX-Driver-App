class BookingStatus {
  static const String waiting = 'waiting';
  static const String onboard = 'onboard';
  static const String offboard = 'offboard';
  static const String cancelled = 'cancelled';
  static const String expired = 'expired';

  static String normalize(String? value) {
    final status = value?.trim().toLowerCase() ?? '';
    switch (status) {
      case 'on_board':
      case 'boarded':
        return onboard;
      case 'off_board':
        return offboard;
      default:
        return status;
    }
  }

  static bool isOnboard(String? value) => normalize(value) == onboard;
  static bool isOffboard(String? value) => normalize(value) == offboard;
  static bool isWaiting(String? value) => normalize(value) == waiting;
  static bool isInactive(String? value) {
    final status = normalize(value);
    return status == offboard || status == cancelled || status == expired;
  }
}
