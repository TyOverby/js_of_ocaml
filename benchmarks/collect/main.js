function make_chart(identifier, data) {
  let container = document.createElement("div");
  container.id = identifier;
  document.body.append(container);

  let catagories = Object.keys(data);
  let bars = Object.values(data);

  // Toggle between using boxplot and errorbar depending on 
  // how many values we have.
  let kind = 'boxplot';
  for (let bar of bars) {
    if (bar.length < 5) {
      kind = 'errorbar'
    }
  }
  if (kind == 'errorbar') {
    for (let bar_idx in bars) {
      let bar = bars[bar_idx];
      bars[bar_idx] = [
        Math.min.apply(null, bar),
        Math.max.apply(null, bar),
      ];
    }
  }

  Highcharts.chart(identifier, {
    chart: {
      zoomType: 'y',
      inverted: true,
      animation: {duration: 0},
    },
    credits: {enabled:false},
    title: { text: identifier },
    xAxis: [{ categories: catagories }],
    yAxis: [{ // Primary yAxis
      min: 0,
      labels: {
        format: '{value} s',
        style: {
          color: Highcharts.getOptions().colors[1]
        }
      },
      title: {
        text: 'Time',
        style: {
          color: Highcharts.getOptions().colors[1]
        }
      }
    }],

    tooltip: { enabled:false, },

    series: [/*{
      name: 'Rainfall',
      type: 'column',
      animation: false,
      yAxis: 1,
      data: [49.9, 71.5, 106.4, 129.2, 144.0, 176.0, 135.6, 148.5, 216.4, 194.1, 95.6, 54.4],
      tooltip: {
        pointFormat: '<span style="font-weight: bold; color: {series.color}">{series.name}</span>: <b>{point.y:.1f} mm</b> '
      }
    },*/ {
      name: 'error',
      type: kind,
      animation: false,
      color: "#ff0000",
      yAxis: 0,
      data: bars,
    }]
  });
}

for (let title in data) {
  make_chart(title, data[title]);
}
