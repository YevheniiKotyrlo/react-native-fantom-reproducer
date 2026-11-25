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
import {Text} from 'react-native';

function renderParagraph() {
  const root = Fantom.createRoot();
  Fantom.runTask(() => {
    root.render(<Text>a<Text>bc</Text></Text>);
  });
  return root.getRenderedOutput({props: []}).toJSONObject();
}

describe('getRenderedOutput() of a paragraph holding a nested Text', () => {
  it('gives the nested Text its children as a list', () => {
    expect(JSON.stringify(renderParagraph())).toBe(
      '{"type":"Paragraph","props":{},"children":["a",{"type":"Text","props":{},"children":["bc"]}]}',
    );
  });

  it("joins the nested Text's children", () => {
    const nested = renderParagraph().children[1];
    expect(nested.children.join('')).toBe('bc');
  });
});
