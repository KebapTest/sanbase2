import sanitizeHtml from 'sanitize-html'
import moment from 'moment'
import ms from 'ms'

const findIndexByDatetime = (labels, datetime) => {
  return labels.findIndex(label => {
    return label.isSame(datetime)
  })
}

const calculateBTCVolume = ({ volume, priceUsd, priceBtc }) => {
  return (parseFloat(volume) / parseFloat(priceUsd)) * parseFloat(priceBtc)
}

const calculateBTCMarketcap = ({ marketcap, priceUsd, priceBtc }) => {
  return (parseFloat(marketcap) / parseFloat(priceUsd)) * parseFloat(priceBtc)
}

const getOrigin = () => {
  if (process.env.NODE_ENV === 'development') {
    return process.env.REACT_APP_FRONTEND_URL || window.location.origin
  }
  return (
    (window.env || {}).FRONTEND_URL ||
    process.env.REACT_APP_FRONTEND_URL ||
    window.location.origin
  )
}

const getAPIUrl = () => {
  if (process.env.NODE_ENV === 'development') {
    return process.env.REACT_APP_BACKEND_URL || window.location.origin
  }
  return (
    (window.env || {}).BACKEND_URL ||
    process.env.REACT_APP_BACKEND_URL ||
    window.location.origin
  )
}

const getConsentUrl = () => {
  if (process.env.NODE_ENV === 'development') {
    return process.env.REACT_APP_BACKEND_URL || window.location.origin
  }
  return (
    (window.env || {}).LOGIN_URL ||
    (window.env || {}).BACKEND_URL ||
    process.env.REACT_APP_BACKEND_URL ||
    window.location.origin
  )
}

const sanitizeMediumDraftHtml = html =>
  sanitizeHtml(html, {
    allowedTags: [
      ...sanitizeHtml.defaults.allowedTags,
      'figure',
      'figcaption',
      'img'
    ],
    allowedAttributes: {
      ...sanitizeHtml.defaults.allowedAttributes,
      '*': ['class', 'id']
    }
  })

const filterProjectsByMarketSegment = (projects, categories) => {
  if (projects === undefined || Object.keys(categories).length === 0) {
    return projects
  }

  return projects.filter(project =>
    Object.keys(categories).includes(project.marketSegment)
  )
}

const binarySearchDirection = {
  MOVE_STOP_TO_LEFT: -1,
  MOVE_START_TO_RIGHT: 1
}

const isCurrentDatetimeBeforeTarget = (current, target) =>
  moment(current.datetime).isBefore(moment(target))

const binarySearchHistoryPriceIndex = (history, targetDatetime) => {
  let start = 0
  let stop = history.length - 1
  let middle = Math.floor((start + stop) / 2)
  while (start < stop) {
    const searchResult = isCurrentDatetimeBeforeTarget(
      history[middle],
      targetDatetime
    )
      ? binarySearchDirection.MOVE_START_TO_RIGHT
      : binarySearchDirection.MOVE_STOP_TO_LEFT

    if (searchResult === binarySearchDirection.MOVE_START_TO_RIGHT) {
      start = middle + 1
    } else {
      stop = middle - 1
    }

    middle = Math.floor((start + stop) / 2)
  }
  // Correcting the result to the first data of post's creation date
  while (!isCurrentDatetimeBeforeTarget(history[middle], targetDatetime)) {
    middle--
  }

  return middle
}

const getStartOfTheDay = () => {
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  return today.toISOString()
}

// Core i5 2.9GHz
// 4 arrays with 90 elements
// No-throttle: mergeTimeseriesByKey-old: ~4.4ms
// No-throttle: mergeTimeseriesByKey-new: ~0.3ms

// x4 throttle: mergeTimeseriesByKey-old: ~13.2ms
// x4 throttle: mergeTimeseriesByKey-new: ~1.3ms

// x6 throttle: mergeTimeseriesByKey-old: ~19.7
// x6 throttle: mergeTimeseriesByKey-new: ~2.1ms

const mergeTimeseriesByKey = ({ timeseries, key: mergeKey }) => {
  const timeseriesLength = timeseries.length

  let longestTSIndex = 0
  for (let i = 1; i < timeseriesLength; i++) {
    if (timeseries[longestTSIndex].length < timeseries[i].length) {
      longestTSIndex = i
    }
  }

  const [mutableLongestTS] = timeseries.splice(longestTSIndex, 1)
  const longestTS = mutableLongestTS.slice()
  const longestTSLastIndex = longestTS.length - 1

  for (const timeserie of timeseries) {
    let longestTSRightIndexBoundary = longestTSLastIndex

    for (
      let timeserieRightIndex = timeserie.length - 1;
      timeserieRightIndex > -1;
      timeserieRightIndex--
    ) {
      while (longestTSRightIndexBoundary > -1) {
        const longestTSData = longestTS[longestTSRightIndexBoundary]
        const timeserieData = timeserie[timeserieRightIndex]
        if (longestTSData[mergeKey] === timeserieData[mergeKey]) {
          longestTS[longestTSRightIndexBoundary] = Object.assign(
            {},
            longestTSData,
            timeserieData
          )
          break
        }
        longestTSRightIndexBoundary--
      }
      if (longestTSRightIndexBoundary === -1) {
        break
      }
    }
  }

  return longestTS
}

const getTimeFromFromString = (time = '1y') => {
  if (isNaN(new Date(time).getDate())) {
    const timeExpression = time.replace(/\d/g, '')
    const multiplier = time.replace(/[a-zA-Z]+/g, '') || 1
    let diff = 0
    if (timeExpression === 'all') {
      diff = 2 * 12 * 30 * 24 * 60 * 60 * 1000
    } else if (timeExpression === 'm') {
      diff = multiplier * 30 * 24 * 60 * 60 * 1000
    } else if (timeExpression === 'w') {
      diff = multiplier * 7 * 24 * 60 * 60 * 1000
    } else {
      diff = ms(time)
    }
    return new Date(+new Date() - diff).toISOString()
  }
  return time
}

const capitalizeStr = string => string.charAt(0).toUpperCase() + string.slice(1)

export {
  findIndexByDatetime,
  calculateBTCVolume,
  calculateBTCMarketcap,
  getOrigin,
  getAPIUrl,
  getConsentUrl,
  sanitizeMediumDraftHtml,
  filterProjectsByMarketSegment,
  binarySearchHistoryPriceIndex,
  getStartOfTheDay,
  mergeTimeseriesByKey,
  getTimeFromFromString,
  capitalizeStr
}
