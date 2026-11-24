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
import {ScrollView, View} from 'react-native';

const hitSlop = {top: 0, left: 0, bottom: 0, right: 80};
const renderOptions = {
  includeLayoutMetrics: true,
  props: ['^layoutMetrics-overflowInset$'],
};

describe("a child's hitSlop past its parent's box", () => {
  it("widens the parent's overflowInset for a View child", () => {
    const root = Fantom.createRoot();
    Fantom.runTask(() => {
      root.render(
        <View collapsable={false} style={{width: 100, height: 100}}>
          <View
            collapsable={false}
            hitSlop={hitSlop}
            style={{width: 40, height: 40}}
          />
        </View>,
      );
    });
    const parent = root.getRenderedOutput(renderOptions).toJSONObject();
    expect(parent.props['layoutMetrics-overflowInset']).toBe(
      '{top:0,right:-20,bottom:-0,left:0}',
    );
  });

  it("widens the parent's overflowInset for a ScrollView child", () => {
    const root = Fantom.createRoot();
    Fantom.runTask(() => {
      root.render(
        <View collapsable={false} style={{width: 100, height: 100}}>
          <ScrollView hitSlop={hitSlop} style={{width: 40, height: 40}} />
        </View>,
      );
    });
    const parent = root.getRenderedOutput(renderOptions).toJSONObject();
    expect(parent.props['layoutMetrics-overflowInset']).toBe(
      '{top:0,right:-20,bottom:-0,left:0}',
    );
  });
});
