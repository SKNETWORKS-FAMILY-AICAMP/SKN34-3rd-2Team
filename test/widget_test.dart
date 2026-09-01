import 'package:flutter_test/flutter_test.dart';

import 'package:playdata_lms/core/constants/app_constants.dart';

void main() {
  test('앱 상수 확인', () {
    expect(AppConstants.appName, 'PLAYDATA');
    expect(AppConstants.resumeSections.length, 11);
  });

  test('Resume 섹션 라벨 매핑 확인', () {
    expect(
      AppConstants.resumeSectionLabels['basicInfo'],
      '기본정보',
    );
  });
}
