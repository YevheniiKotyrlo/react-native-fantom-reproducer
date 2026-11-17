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

import * as Fantom from '@react-native/fantom';
import * as React from 'react';
import {UIManager, View} from 'react-native';

describe('UIManager.hasViewManagerConfig', () => {
  it('renders View', () => {
    const root = Fantom.createRoot();
    Fantom.runTask(() => {
      root.render(<View nativeID="view" />);
    });
    expect(root.getRenderedOutput().toJSX()).toEqual(
      <rn-view nativeID="view" />,
    );
  });

  it('answers true for View', () => {
    expect(UIManager.hasViewManagerConfig('View')).toBe(true);
  });
});
