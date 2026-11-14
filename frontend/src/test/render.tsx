import { MantineProvider } from '@mantine/core'
import { render } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import App from '../App'
import { defaultStyleName, getStyleTheme } from '../themes'

// Render the whole application at a path, inside the providers main.tsx mounts.
export function renderApp(path: string) {
  return render(
    <MantineProvider theme={getStyleTheme(defaultStyleName)}>
      <MemoryRouter initialEntries={[path]}>
        <App />
      </MemoryRouter>
    </MantineProvider>,
  )
}
