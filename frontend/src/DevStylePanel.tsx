import {
  ActionIcon,
  Affix,
  Button,
  Chip,
  Divider,
  Group,
  Paper,
  ScrollArea,
  SegmentedControl,
  Stack,
  Text,
  useMantineColorScheme,
} from '@mantine/core'
import { IconPalette, IconX } from '@tabler/icons-react'
import { useState } from 'react'
import {
  getStylePreset,
  layoutDimensions,
  resolvePreset,
  stylePresets,
  type DevStyleState,
  type StyleLayout,
} from './themes'

// Development scaffolding: compares candidate styles live and lets layout
// dimensions be mixed across presets, one click per change. Kept while
// features are built; removed together with the extra presets in themes.ts
// once a style is finalized. It renders whatever themes.ts declares, so new
// design dimensions appear here without panel changes.
function DevStylePanel({
  state,
  onChange,
}: {
  state: DevStyleState
  onChange: (state: DevStyleState) => void
}) {
  const { colorScheme, setColorScheme } = useMantineColorScheme()
  const [opened, setOpened] = useState(true)
  const effectiveLayout = resolvePreset(state).layout
  const baseLayout = getStylePreset(state.base).layout
  const hasOverrides = Object.keys(state.overrides).length > 0

  if (!opened) {
    return (
      <Affix position={{ bottom: 16, right: 16 }}>
        <Button
          leftSection={<IconPalette size={16} />}
          variant="default"
          size="xs"
          onClick={() => setOpened(true)}
        >
          Style
        </Button>
      </Affix>
    )
  }

  const setDimension = (key: keyof StyleLayout, value: string) => {
    const overrides = { ...state.overrides }
    if (value === baseLayout[key]) {
      delete overrides[key]
    } else {
      overrides[key] = value as never
    }
    onChange({ ...state, overrides })
  }

  return (
    <Affix position={{ bottom: 16, right: 16 }}>
      {/* Wide enough that each chip row stays on one line. */}
      <Paper withBorder shadow="md" w="max-content" maw="calc(100vw - 32px)">
        <ScrollArea.Autosize mah="calc(100vh - 32px)" p="sm">
          <Stack gap="sm">
            <Group justify="space-between" wrap="nowrap">
              <Text size="xs" fw={700} tt="uppercase" c="dimmed">
                Style preview (dev)
              </Text>
              <ActionIcon
                variant="subtle"
                color="gray"
                size="sm"
                aria-label="Collapse the style panel"
                onClick={() => setOpened(false)}
              >
                <IconX size={14} />
              </ActionIcon>
            </Group>

            <Text size="xs" c="dimmed">
              Theme
            </Text>
            <Chip.Group
              multiple={false}
              value={state.base}
              onChange={(base) => onChange({ ...state, base })}
            >
              <Group gap={6} wrap="nowrap">
                {stylePresets.map((preset) => (
                  <Chip key={preset.name} value={preset.name} size="xs">
                    {preset.label}
                  </Chip>
                ))}
              </Group>
            </Chip.Group>

            {layoutDimensions.map((dimension) => (
              <div key={dimension.key}>
                <Text size="xs" c="dimmed" mb={4}>
                  {dimension.label}
                </Text>
                <Chip.Group
                  multiple={false}
                  value={effectiveLayout[dimension.key]}
                  onChange={(value) => setDimension(dimension.key, value)}
                >
                  <Group gap={6} wrap="nowrap">
                    {dimension.options.map((option) => (
                      <Chip key={option.value} value={option.value} size="xs">
                        {option.label}
                      </Chip>
                    ))}
                  </Group>
                </Chip.Group>
              </div>
            ))}

            {hasOverrides && (
              <Button
                variant="subtle"
                size="compact-xs"
                onClick={() => onChange({ ...state, overrides: {} })}
              >
                Reset layout to {getStylePreset(state.base).label}
              </Button>
            )}

            <Divider />
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
        </ScrollArea.Autosize>
      </Paper>
    </Affix>
  )
}

export default DevStylePanel
