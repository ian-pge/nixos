.pragma library

function boundedWidth(contentWidth, minimumWidth, maximumWidth) {
  return Math.ceil(Math.min(maximumWidth,
    Math.max(minimumWidth, contentWidth)));
}

function widestText(metrics, values) {
  let width = 0;
  for (let index = 0; index < values.length; ++index) {
    const value = values[index];
    if (value === undefined || value === null)
      continue;
    width = Math.max(width, metrics.advanceWidth(value.toString()));
  }
  return width;
}
