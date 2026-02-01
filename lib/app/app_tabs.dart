import 'package:flutter/foundation.dart';

class AppTabs {
  AppTabs._();

  static final index = ValueNotifier<int>(0);

  static void go(int i) {
    if (i < 0) i = 0;
    if (i > 3) i = 3;
    index.value = i;
  }
}
