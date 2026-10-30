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

import * as TurboModuleRegistry from '../TurboModuleRegistry';

describe('TurboModuleRegistry', () => {
  it('answers the same module for every lookup of one name', () => {
    expect(TurboModuleRegistry.get('SourceCode')).not.toBeNull();
    const first = TurboModuleRegistry.get('SourceCode');
    const second = TurboModuleRegistry.get('SourceCode');
    expect(first === second).toBe(true);
  });
});
