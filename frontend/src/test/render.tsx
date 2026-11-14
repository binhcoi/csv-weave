import { MantineProvider } from '@mantine/core'
import { render } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import App from '../App'
import { defaultStyleName, getStylePreset, StylePresetContext } from '../themes'

// Render the whole application at a path, inside the providers Root.tsx mounts,
// using the named style preset (the default one when omitted).
export function renderApp(path: string, presetName: string = defaultStyleName) {
  const preset = getStylePreset(presetName)

  return render(
    <StylePresetContext.Provider value={preset}>
      <MantineProvider theme={preset.theme}>
        <MemoryRouter initialEntries={[path]}>
          <App />
        </MemoryRouter>
      </MantineProvider>
    </StylePresetContext.Provider>,
  )
}
