import { Badge, Button, Group, Stack, Table, Text, Title } from '@mantine/core'
import { useDocumentTitle } from '@mantine/hooks'
import { IconPlus } from '@tabler/icons-react'
import PreviewNote from '../components/PreviewNote'

const exampleFileTypes = [
  {
    name: 'Customer import',
    description: 'Raw customer rows as exported by the legacy system',
    columns: 8,
    rules: 14,
  },
  {
    name: 'CRM contacts',
    description: 'Contact format accepted by the CRM bulk importer',
    columns: 6,
    rules: 9,
  },
  {
    name: 'Order lines',
    description: 'One row per ordered item, with totals in cents',
    columns: 11,
    rules: 21,
  },
]

function FileTypesPage() {
  useDocumentTitle('File types · CSVWeave')

  return (
    <Stack gap="lg">
      <Group justify="space-between" align="center">
        <Title order={1}>File types</Title>
        <Button leftSection={<IconPlus size={16} />} disabled>
          New file type
        </Button>
      </Group>
      <Text c="dimmed" maw="42rem">
        A file type is a reusable CSV format: its ordered columns and the validation rules on each
        column. Validation runs check a file against its type; transformation maps convert between
        two types.
      </Text>
      <PreviewNote>
        Example data to settle the look and feel. Creating and editing file types arrives with the
        editor milestone.
      </PreviewNote>
      <Table striped highlightOnHover withTableBorder>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Name</Table.Th>
            <Table.Th>Description</Table.Th>
            <Table.Th>Columns</Table.Th>
            <Table.Th>Validation rules</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {exampleFileTypes.map((fileType) => (
            <Table.Tr key={fileType.name}>
              <Table.Td fw={600}>{fileType.name}</Table.Td>
              <Table.Td>{fileType.description}</Table.Td>
              <Table.Td>
                <Badge variant="light">{fileType.columns}</Badge>
              </Table.Td>
              <Table.Td>
                <Badge variant="light" color="gray">
                  {fileType.rules}
                </Badge>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Stack>
  )
}

export default FileTypesPage
