/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @flow strict-local
 * @fantom_flags preventShadowTreeCommitExhaustion:true
 * @format
 */

import '@react-native/fantom/src/setUpDefaultReactNativeEnvironment';

import * as Fantom from '@react-native/fantom';
import * as React from 'react';
import {View} from 'react-native';

describe('a surface stopped under contention', () => {
  it('commits its empty tree in the locked attempt', () => {
    const root = Fantom.createRoot();

    Fantom.runTask(() => {
      root.render(<View nativeID="view" />);
    });

    root.destroy();
  });
});
