import { MantineProvider } from '@mantine/core'
import { useLocalStorage } from '@mantine/hooks'
import { BrowserRouter } from 'react-router'
import App from './App'
import DevStylePanel from './DevStylePanel'
import { defaultStyleName, getStyleTheme } from './themes'

// Mounts the providers around the app. The style state and DevStylePanel are
// temporary, removed once a visual style is chosen.
function Root() {
  const [styleName, setStyleName] = useLocalStorage({
    key: 'csvweave-dev-style',
    defaultValue: defaultStyleName,
  })

  return (
    <MantineProvider theme={getStyleTheme(styleName)} defaultColorScheme="auto">
      <BrowserRouter>
        <App />
      </BrowserRouter>
      <DevStylePanel value={styleName} onChange={setStyleName} />
    </MantineProvider>
  )
}

export default Root
