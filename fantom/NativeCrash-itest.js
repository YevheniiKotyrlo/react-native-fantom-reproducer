/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @flow strict-local
 * @format
 */

import '@react-native/fantom/src/setUpDefaultReactNativeEnvironment';

import NativeFantom from '../../../../packages/react-native/src/private/testing/fantom/specs/NativeFantom';

describe('a crash in native code', () => {
  it('ends the tester with a stack that names the crashing function', () => {
    NativeFantom.clearAllImages();
  });
});
