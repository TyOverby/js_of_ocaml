function make_chart(identifier, data, data2) {
  let container = document.createElement("div");
  container.id = identifier;
  document.body.append(container);

  if (Object.keys(data).length !== Object.keys(data2).length) {
    container.innerText = "Not the same values for " + identifier;
    console.log(data, data2);
    return;
  }

  let catagories = Object.keys(data);
  let bars = Object.values(data);
  let bars2 = Object.values(data2);

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

  let bart

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
      name: 'before-error',
      type: kind,
      animation: false,
      color: "#ff0000",
      yAxis: 0,
      data: bars,
    }, {
      name: 'error-after',
      type: kind,
      animation: false,
      color: "#0000ff",
      yAxis: 0,
      data: bars2,
    }]
  });
}

for (let title in data) {
  make_chart(title, data[title], data2[title]);
}
