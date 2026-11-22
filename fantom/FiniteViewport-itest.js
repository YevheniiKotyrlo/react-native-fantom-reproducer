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
import {View} from 'react-native';

describe('Fantom.createRoot()', () => {
  it('lays out a View of the root', () => {
    const root = Fantom.createRoot();
    Fantom.runTask(() => {
      root.render(<View style={{height: 10}} collapsable={false} />);
    });
    expect(
      root
        .getRenderedOutput({
          includeLayoutMetrics: true,
          props: ['^layoutMetrics-frame$'],
        })
        .toJSX(),
    ).toEqual(<rn-view layoutMetrics-frame="{x:0,y:0,width:390,height:10}" />);
  });
});
