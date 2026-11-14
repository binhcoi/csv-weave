import { Box, Card, Group, Paper, SimpleGrid, Stack, Table, Text } from '@mantine/core'
import type { ReactNode } from 'react'
import { useStylePreset } from '../themes'

export interface CollectionField<T> {
  key: string
  label: string
  render: (item: T) => ReactNode
}

interface CollectionProps<T> {
  items: T[]
  /** The first field is the record's title; the second doubles as its subtitle in panel rows. */
  fields: CollectionField<T>[]
  itemKey: (item: T) => string | number
}

// Presents a collection of records the way the active style preset dictates:
// panel rows, a table, a card grid, a stacked list, or log lines.
function Collection<T>({ items, fields, itemKey }: CollectionProps<T>) {
  const { presentation, density } = useStylePreset().layout
  const [titleField, ...detailFields] = fields

  if (presentation === 'panels') {
    // Full-width rows, one bordered panel per record: title and subtitle on the
    // left, the remaining fields as labeled values on the right.
    const [subtitleField, ...sideFields] = detailFields
    return (
      <Stack gap="sm">
        {items.map((item) => (
          <Card key={itemKey(item)} withBorder shadow="xs">
            <Group justify="space-between" align="flex-start" gap="md">
              <Box maw="24rem">
                <Text fw={600}>{titleField.render(item)}</Text>
                {subtitleField && (
                  <Box mt={4} fz="sm" c="dimmed">
                    {subtitleField.render(item)}
                  </Box>
                )}
              </Box>
              <Group gap="xl" align="flex-start">
                {sideFields.map((field) => (
                  <div key={field.key}>
                    <Text size="xs" c="dimmed" tt="uppercase">
                      {field.label}
                    </Text>
                    <Box mt={2} fz="sm">
                      {field.render(item)}
                    </Box>
                  </div>
                ))}
              </Group>
            </Group>
          </Card>
        ))}
      </Stack>
    )
  }

  if (presentation === 'cards') {
    return (
      <SimpleGrid cols={{ base: 1, md: 2, lg: 3 }}>
        {items.map((item) => (
          <Card key={itemKey(item)} withBorder>
            <Stack gap="sm">
              <Text fw={600}>{titleField.render(item)}</Text>
              {detailFields.map((field) => (
                <div key={field.key}>
                  <Text size="xs" c="dimmed" tt="uppercase">
                    {field.label}
                  </Text>
                  <Box mt={2}>{field.render(item)}</Box>
                </div>
              ))}
            </Stack>
          </Card>
        ))}
      </SimpleGrid>
    )
  }

  if (presentation === 'list') {
    return (
      <Stack gap={0}>
        {items.map((item, index) => (
          <Box
            key={itemKey(item)}
            py="md"
            style={
              index > 0 ? { borderTop: '1px solid var(--mantine-color-default-border)' } : undefined
            }
          >
            <Text fw={600}>{titleField.render(item)}</Text>
            <Group gap="lg" mt={6} wrap="wrap">
              {detailFields.map((field) => (
                <Group key={field.key} gap={6} align="baseline" wrap="nowrap">
                  <Text size="xs" c="dimmed" span>
                    {field.label}:
                  </Text>
                  <Box component="span" fz="sm">
                    {field.render(item)}
                  </Box>
                </Group>
              ))}
            </Group>
          </Box>
        ))}
      </Stack>
    )
  }

  if (presentation === 'log') {
    // Console output: numbered lines, title, then label=value pairs.
    return (
      <Paper withBorder p="md" ff="monospace">
        <Stack gap={8}>
          {items.map((item, index) => (
            <Group key={itemKey(item)} gap="md" align="baseline" wrap="wrap">
              <Text span size="sm" c="dimmed">
                {String(index + 1).padStart(2, '0')}
              </Text>
              <Text span size="sm" fw={700}>
                {titleField.render(item)}
              </Text>
              {detailFields.map((field) => (
                <Group key={field.key} gap={2} align="baseline" wrap="nowrap">
                  <Text span size="sm" c="dimmed">
                    {field.label.toLowerCase().replaceAll(' ', '_')}=
                  </Text>
                  <Box component="span" fz="sm">
                    {field.render(item)}
                  </Box>
                </Group>
              ))}
            </Group>
          ))}
        </Stack>
      </Paper>
    )
  }

  const dense = density === 'compact'
  return (
    <Table withTableBorder highlightOnHover striped={dense} verticalSpacing={dense ? 4 : 'sm'}>
      <Table.Thead>
        <Table.Tr>
          {fields.map((field) => (
            <Table.Th key={field.key}>{field.label}</Table.Th>
          ))}
        </Table.Tr>
      </Table.Thead>
      <Table.Tbody>
        {items.map((item) => (
          <Table.Tr key={itemKey(item)}>
            {fields.map((field, index) => (
              <Table.Td key={field.key} fw={index === 0 ? 600 : undefined}>
                {field.render(item)}
              </Table.Td>
            ))}
          </Table.Tr>
        ))}
      </Table.Tbody>
    </Table>
  )
}

export default Collection
