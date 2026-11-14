import { createTheme, type MantineTheme, type MantineThemeOverride } from '@mantine/core'

// Candidate visual styles for CSVWeave. A temporary dev-only panel (DevStylePanel)
// switches between them; once one is chosen this file collapses to a single theme.

export interface StyleOption {
  name: string
  label: string
  description: string
  theme: MantineThemeOverride
}

const monoStack =
  'ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace'

export const styleOptions: StyleOption[] = [
  {
    name: 'loom',
    label: 'Loom',
    description: 'Calm teal, soft corners, system fonts.',
    theme: createTheme({
      primaryColor: 'teal',
      primaryShade: { light: 7, dark: 5 },
      defaultRadius: 'md',
      cursorType: 'pointer',
      headings: { fontWeight: '650' },
      other: { logoGradient: { from: 'teal', to: 'cyan' } },
    }),
  },
  {
    name: 'ledger',
    label: 'Ledger',
    description: 'Indigo, square corners, dense and businesslike.',
    theme: createTheme({
      primaryColor: 'indigo',
      defaultRadius: 'xs',
      cursorType: 'pointer',
      headings: { fontWeight: '700' },
      other: { logoGradient: { from: 'indigo', to: 'blue' } },
    }),
  },
  {
    name: 'harvest',
    label: 'Harvest',
    description: 'Warm orange, very round, light headings.',
    theme: createTheme({
      primaryColor: 'orange',
      defaultRadius: 'xl',
      cursorType: 'pointer',
      headings: { fontWeight: '500' },
      other: { logoGradient: { from: 'orange', to: 'yellow' } },
    }),
  },
  {
    name: 'inkwell',
    label: 'Inkwell',
    description: 'Violet with serif headings, editorial.',
    theme: createTheme({
      primaryColor: 'violet',
      defaultRadius: 'sm',
      cursorType: 'pointer',
      headings: {
        fontFamily: 'Georgia, Cambria, "Times New Roman", serif',
        fontWeight: '600',
      },
      other: { logoGradient: { from: 'violet', to: 'grape' } },
    }),
  },
  {
    name: 'terminal',
    label: 'Terminal',
    description: 'Green on monospace, austere data tool.',
    theme: createTheme({
      primaryColor: 'green',
      defaultRadius: 2,
      cursorType: 'pointer',
      fontFamily: monoStack,
      headings: { fontFamily: monoStack, fontWeight: '600' },
      other: { logoGradient: { from: 'green', to: 'lime' } },
    }),
  },
]

export const defaultStyleName = styleOptions[0].name

export function getStyleTheme(name: string | undefined): MantineThemeOverride {
  return (styleOptions.find((option) => option.name === name) ?? styleOptions[0]).theme
}

// The header logo follows the active style's gradient.
export function logoGradient(theme: MantineTheme): { from: string; to: string } {
  return (
    (theme.other.logoGradient as { from: string; to: string } | undefined) ?? {
      from: 'teal',
      to: 'cyan',
    }
  )
}
