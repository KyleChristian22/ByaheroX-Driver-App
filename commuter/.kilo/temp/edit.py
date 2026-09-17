import pathlib
p = pathlib.Path(r"C:\Users\chave\Desktop\backupByaheroX\commuter\lib\presentation\screens\home\home_screen.dart")
content = p.read_text()
old = """      if (authViewModel.isGuest &&
          firebase_auth.FirebaseAuth.instance.currentUser == null) {
        debugPrint(
          'HomeScreen: Guest Mode entered without FirebaseAuth user. '
          'Signing in anonymously before starting listeners.',
        );
        await authViewModel.loginAsGuest();
      }"""
new = """      // Do NOT automatically sign in as guest here. Guest Mode should
      // only be activated when the user explicitly taps "Continue as
      // Guest" on the welcome screen. Auto-sign-in creates an anonymous
      // Firebase session that persists across app restarts, making it
      // feel like the app is forcing guest mode."""
if old in content:
    content = content.replace(old, new)
    p.write_text(content)
    print("Replacement successful")
else:
    print("OLD STRING NOT FOUND")
