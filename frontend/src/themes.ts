import { createTheme, type MantineTheme, type MantineThemeOverride } from '@mantine/core'
import { createContext, useContext } from 'react'

// Candidate visual styles for CSVWeave. Each preset is a whole personality:
// Mantine theme tokens plus layout structure (navigation placement, content
// width, density) and how collections of records are presented. A temporary
// dev-only panel (DevStylePanel) switches between them; once one is chosen,
// this file collapses to a single theme and fixed layout.

export interface StyleLayout {
  /** Where the main navigation lives and how it looks. */
  nav: 'sidebar' | 'sidebar-compact' | 'topbar-pills' | 'header-tabs' | 'topbar-text'
  /** Header treatment: neutral surface or filled with the primary color. */
  headerStyle: 'plain' | 'filled'
  /** Width of the page content: edge to edge, a wide centered column, or a narrow one. */
  contentWidth: 'full' | 'wide' | 'narrow'
  /** Overall spacing scale. */
  density: 'airy' | 'comfortable' | 'compact'
  /** How collections of records (file types, maps, runs) are presented. */
  presentation: 'panels' | 'table' | 'cards' | 'list' | 'log'
}

export interface StylePreset {
  name: string
  label: string
  description: string
  theme: MantineThemeOverride
  layout: StyleLayout
}

const monoStack =
  'ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace'

export const stylePresets: StylePreset[] = [
  {
    name: 'loom',
    label: 'Loom',
    description: 'Teal · sidebar · full width · records as panel rows',
    theme: createTheme({
      primaryColor: 'teal',
      primaryShade: { light: 7, dark: 5 },
      defaultRadius: 'md',
      cursorType: 'pointer',
      headings: { fontWeight: '650' },
      other: { logoGradient: { from: 'teal', to: 'cyan' } },
    }),
    layout: {
      nav: 'sidebar',
      headerStyle: 'plain',
      contentWidth: 'full',
      density: 'comfortable',
      presentation: 'panels',
    },
  },
  {
    name: 'ledger',
    label: 'Ledger',
    description: 'Indigo · filled header · compact sidebar · dense tables',
    theme: createTheme({
      primaryColor: 'indigo',
      defaultRadius: 'xs',
      cursorType: 'pointer',
      headings: { fontWeight: '700' },
      other: { logoGradient: { from: 'indigo', to: 'blue' } },
    }),
    layout: {
      nav: 'sidebar-compact',
      headerStyle: 'filled',
      contentWidth: 'full',
      density: 'compact',
      presentation: 'table',
    },
  },
  {
    name: 'harvest',
    label: 'Harvest',
    description: 'Orange · pill top bar · airy centered column · card grid',
    theme: createTheme({
      primaryColor: 'orange',
      defaultRadius: 'xl',
      cursorType: 'pointer',
      headings: { fontWeight: '500' },
      other: { logoGradient: { from: 'orange', to: 'yellow' } },
    }),
    layout: {
      nav: 'topbar-pills',
      headerStyle: 'plain',
      contentWidth: 'wide',
      density: 'airy',
      presentation: 'cards',
    },
  },
  {
    name: 'inkwell',
    label: 'Inkwell',
    description: 'Violet serif · underline tabs · reading column · stacked list',
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
    layout: {
      nav: 'header-tabs',
      headerStyle: 'plain',
      contentWidth: 'narrow',
      density: 'comfortable',
      presentation: 'list',
    },
  },
  {
    name: 'terminal',
    label: 'Terminal',
    description: 'Green mono · text top bar · records as log lines',
    theme: createTheme({
      primaryColor: 'green',
      defaultRadius: 2,
      cursorType: 'pointer',
      fontFamily: monoStack,
      headings: { fontFamily: monoStack, fontWeight: '600' },
      other: { logoGradient: { from: 'green', to: 'lime' } },
    }),
    layout: {
      nav: 'topbar-text',
      headerStyle: 'plain',
      contentWidth: 'full',
      density: 'compact',
      presentation: 'log',
    },
  },
]

export const defaultStyleName = stylePresets[0].name

export function getStylePreset(name: string | undefined): StylePreset {
  return stylePresets.find((preset) => preset.name === name) ?? stylePresets[0]
}

// The dev panel's state: a base preset (theme tokens and default layout) plus
// per-dimension layout overrides, so dimensions can be mixed across presets.
export interface DevStyleState {
  base: string
  overrides: Partial<StyleLayout>
}

export function resolvePreset(state: DevStyleState): StylePreset {
  const base = getStylePreset(state.base)
  return { ...base, layout: { ...base.layout, ...state.overrides } }
}

// Choices per layout dimension, for the dev panel's controls. The panel renders
// one chip row per entry, so a new design dimension (for example a form layout
// once the editors are built) extends the panel by being appended here, added
// to StyleLayout and each preset, and consumed where it applies.
// Density stays preset-defined only: its visual difference is too small to be
// worth a control of its own.
export const layoutDimensions: {
  key: keyof StyleLayout
  label: string
  options: { value: string; label: string }[]
}[] = [
  {
    key: 'nav',
    label: 'Navigation',
    options: [
      { value: 'sidebar', label: 'Sidebar' },
      { value: 'sidebar-compact', label: 'Compact side' },
      { value: 'topbar-pills', label: 'Pills' },
      { value: 'header-tabs', label: 'Tabs' },
      { value: 'topbar-text', label: 'Text' },
    ],
  },
  {
    key: 'headerStyle',
    label: 'Header',
    options: [
      { value: 'plain', label: 'Plain' },
      { value: 'filled', label: 'Filled' },
    ],
  },
  {
    key: 'contentWidth',
    label: 'Content width',
    options: [
      { value: 'full', label: 'Full' },
      { value: 'wide', label: 'Wide' },
      { value: 'narrow', label: 'Narrow' },
    ],
  },
  {
    key: 'presentation',
    label: 'Records',
    options: [
      { value: 'panels', label: 'Panels' },
      { value: 'table', label: 'Table' },
      { value: 'cards', label: 'Cards' },
      { value: 'list', label: 'List' },
      { value: 'log', label: 'Log' },
    ],
  },
]

export const StylePresetContext = createContext<StylePreset>(stylePresets[0])

export function useStylePreset(): StylePreset {
  return useContext(StylePresetContext)
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
