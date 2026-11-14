import { Affix, Paper, SegmentedControl, Stack, Text, useMantineColorScheme } from '@mantine/core'
import { styleOptions } from './themes'

// Temporary, development-only: compares the candidate visual styles live.
// Remove together with the extra entries in themes.ts once a style is chosen.
function DevStylePanel({ value, onChange }: { value: string; onChange: (name: string) => void }) {
  const { colorScheme, setColorScheme } = useMantineColorScheme()
  const current = styleOptions.find((option) => option.name === value)

  return (
    <Affix position={{ bottom: 16, right: 16 }}>
      <Paper withBorder shadow="md" p="sm" w={230}>
        <Stack gap="xs">
          <Text size="xs" fw={700} tt="uppercase" c="dimmed">
            Style preview (dev)
          </Text>
          <SegmentedControl
            orientation="vertical"
            fullWidth
            size="xs"
            data={styleOptions.map((option) => ({ value: option.name, label: option.label }))}
            value={value}
            onChange={onChange}
          />
          {current && (
            <Text size="xs" c="dimmed">
              {current.description}
            </Text>
          )}
          <SegmentedControl
            fullWidth
            size="xs"
            data={[
              { value: 'light', label: 'Light' },
              { value: 'auto', label: 'Auto' },
              { value: 'dark', label: 'Dark' },
            ]}
            value={colorScheme}
            onChange={(value) => setColorScheme(value as 'light' | 'auto' | 'dark')}
          />
        </Stack>
      </Paper>
    </Affix>
  )
}

export default DevStylePanel
