class TerminalConstants {
  static const String lucbanTerminal = 'Lucban Terminal';
  static const String staCruzTerminal = 'Sta.Cruz Terminal';
  
  static const String lucbanCode = 'lucban';
  static const String staCruzCode = 'sta_cruz';
  
  static String fromCode(String code) {
    if (code == lucbanCode) return lucbanTerminal;
    if (code == staCruzCode) return staCruzTerminal;
    return code;
  }
  
  static String toCode(String terminal) {
    if (terminal == lucbanTerminal) return lucbanCode;
    if (terminal == staCruzTerminal) return staCruzCode;
    return terminal;
  }
}