import { MantineProvider } from '@mantine/core'
import { useLocalStorage } from '@mantine/hooks'
import { BrowserRouter } from 'react-router'
import App from './App'
import DevStylePanel from './DevStylePanel'
import { defaultStyleName, resolvePreset, StylePresetContext, type DevStyleState } from './themes'

const defaultState: DevStyleState = { base: defaultStyleName, overrides: {} }

function deserializeState(value: string | undefined): DevStyleState {
  if (!value) return defaultState
  try {
    const parsed: unknown = JSON.parse(value)
    if (typeof parsed === 'string') return { base: parsed, overrides: {} }
    return { ...defaultState, ...(parsed as Partial<DevStyleState>) }
  } catch {
    // Earlier versions stored the bare preset name.
    return { base: value, overrides: {} }
  }
}

// Mounts the providers around the app. The style state and DevStylePanel are
// development scaffolding, kept while features are built until a style is final.
function Root() {
  const [styleState, setStyleState] = useLocalStorage<DevStyleState>({
    key: 'csvweave-dev-style',
    defaultValue: defaultState,
    serialize: JSON.stringify,
    deserialize: deserializeState,
  })
  const preset = resolvePreset(styleState)

  return (
    <StylePresetContext.Provider value={preset}>
      <MantineProvider theme={preset.theme} defaultColorScheme="auto">
        <BrowserRouter>
          <App />
        </BrowserRouter>
        <DevStylePanel state={styleState} onChange={setStyleState} />
      </MantineProvider>
    </StylePresetContext.Provider>
  )
}

export default Root
